import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parents[1] / "excelCheckboxes/globalPlugins/excelCheckboxes"))

import checkboxState  # noqa: E402


class FakeColumns:
	def __init__(self, count):
		self.Count = count


class FakeCell:
	"""A cell or merged area; row/column/width say where it is, for its neighbours."""

	def __init__(self, sheet, area, row=1, column=1, width=1):
		self.Worksheet = sheet
		self.MergeArea = self
		self.area = area
		self.Row = row
		self.Column = column
		self.Columns = FakeColumns(width)

	def Address(self, rowAbsolute, columnAbsolute):
		assert (rowAbsolute, columnAbsolute) == (False, False)
		return self.area


class FakeTextCell:
	def __init__(self, text):
		self.Text = text


class FakeControl:
	def __init__(self, value):
		self.Value = value


class FakeOLEFormat:
	def __init__(self, value):
		self.Object = FakeControl(value)


class FakeShape:
	def __init__(self, sheet, area, value=-4146, name="", shapeType=8, controlType=1, row=1, column=1, width=1):
		self.Type = shapeType
		self.FormControlType = controlType
		self.AlternativeText = name
		self.TopLeftCell = FakeCell(sheet, area, row, column, width)
		self.OLEFormat = FakeOLEFormat(value)


class FakeShapes:
	def __init__(self):
		self.items = []
		self.reads = 0

	@property
	def Count(self):
		return len(self.items)

	def Item(self, index):
		self.reads += 1
		return self.items[index - 1]


class FakeWorkbook:
	FullName = "C:\\PRAE.xlsx"


class FakeSheet:
	Name = "PRAE"
	Parent = FakeWorkbook()

	def __init__(self):
		self.Shapes = FakeShapes()
		self.texts = {}
		self.cellReads = 0

	def Cells(self, row, column):
		self.cellReads += 1
		return FakeTextCell(self.texts.get((row, column), ""))


class LabelTests(unittest.TestCase):
	def test_addsMarkAndDropsTheBoxGlyph(self):
		self.assertEqual(checkboxState.labelWithMark("r Übungsleiter:in", True), "[X] Übungsleiter:in")
		self.assertEqual(checkboxState.labelWithMark("r Ja (Nebenberuf)", False), "[ ] Ja (Nebenberuf)")
		self.assertEqual(checkboxState.labelWithMark("\uf072 Trainer:in", True), "[X] Trainer:in")

	def test_keepsWordsThatStartWithR(self):
		self.assertEqual(checkboxState.labelWithMark("Rennleiter:in", False), "[ ] Rennleiter:in")
		self.assertEqual(checkboxState.labelWithMark("rot", True), "[X] rot")

	def test_emptyCellUsesTheControlName(self):
		self.assertEqual(checkboxState.labelWithMark("", False, "Richtigkeitsvermerk"), "[ ] Richtigkeitsvermerk")
		self.assertEqual(checkboxState.labelWithMark(None, True), "[X]")


class NameTests(unittest.TestCase):
	def test_knowsWhenTheCellNamesItsBox(self):
		self.assertTrue(checkboxState.hasLabel("r Trainer:in"))
		self.assertFalse(checkboxState.hasLabel(""))
		self.assertFalse(checkboxState.hasLabel("r "))
		self.assertFalse(checkboxState.hasLabel(None))

	def test_shortensANeighbourToItsColon(self):
		self.assertEqual(
			checkboxState.shortLabel(
				"Richtigkeitsvermerk: Dieser Beleg wird bei keinem anderen Fördergeber zur Abrechnung vorgelegt"
			),
			"Richtigkeitsvermerk",
		)
		self.assertEqual(checkboxState.shortLabel("  Bestätigung  "), "Bestätigung")
		self.assertEqual(checkboxState.shortLabel("Masseur:in"), "Masseur:in")
		self.assertEqual(checkboxState.shortLabel("Überweisung mittels:"), "Überweisung mittels")
		self.assertEqual(checkboxState.shortLabel(": nur Text"), ": nur Text")
		self.assertEqual(checkboxState.shortLabel(""), "")


class SpeechTests(unittest.TestCase):
	def test_saysTheStateInWordsAfterTheLabel(self):
		self.assertEqual(checkboxState.spokenLabel("r Übungsleiter:in", True), "Übungsleiter:in ausgewählt")
		self.assertEqual(checkboxState.spokenLabel("r Trainer:in", False), "Trainer:in nicht ausgewählt")

	def test_emptyCellSaysTheControlName(self):
		self.assertEqual(
			checkboxState.spokenLabel("", False, "Richtigkeitsvermerk"),
			"Richtigkeitsvermerk nicht ausgewählt",
		)

	def test_swapsTheReportedTextInsideLongerSpeech(self):
		command = object()
		sequence = [command, "[X] Trainer:in  B9", "Spalte B"]
		self.assertEqual(
			checkboxState.replaceInSpeech(sequence, "[X] Trainer:in", "Trainer:in ausgewählt"),
			[command, "Trainer:in ausgewählt  B9", "Spalte B"],
		)

	def test_leavesOtherTextWithMarksAlone(self):
		self.assertEqual(
			checkboxState.replaceInSpeech(["[X] Notiz"], "[X] Trainer:in", "Trainer:in ausgewählt"),
			["[X] Notiz"],
		)


class FinderTests(unittest.TestCase):
	def setUp(self):
		self.sheet = FakeSheet()
		self.finder = checkboxState.CheckboxFinder()

	def test_sheetWithoutShapes(self):
		self.assertIsNone(self.finder.find(FakeCell(self.sheet, "A1")))

	def test_cellWithoutCheckbox(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P9:W9"))
		self.assertIsNone(self.finder.find(FakeCell(self.sheet, "A1")))

	def test_findsCheckboxOnMergedCell(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P9:W9", value=1, name="Übungsleiter:in"))
		self.assertEqual(self.finder.find(FakeCell(self.sheet, "P9:W9")), (True, "Übungsleiter:in"))

	def test_stateFollowsTheCheckbox(self):
		shape = FakeShape(self.sheet, "A26", value=1)
		self.sheet.Shapes.items.append(shape)
		cell = FakeCell(self.sheet, "A26")
		self.assertTrue(self.finder.find(cell)[0])
		shape.OLEFormat.Object.Value = -4146
		self.assertFalse(self.finder.find(cell)[0])
		shape.OLEFormat.Object.Value = 1
		self.assertTrue(self.finder.find(cell)[0])

	def test_mixedStateIsNotChecked(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "A26", value=2))
		self.assertFalse(self.finder.find(FakeCell(self.sheet, "A26"))[0])

	def test_ignoresPicturesAndOtherControls(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "A1", shapeType=13))
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "A2", controlType=2))
		self.assertIsNone(self.finder.find(FakeCell(self.sheet, "A1")))
		self.assertIsNone(self.finder.find(FakeCell(self.sheet, "A2")))

	def test_scansTheShapesOnlyOnce(self):
		self.sheet.Shapes.items.extend(FakeShape(self.sheet, f"A{row}") for row in range(1, 17))
		self.finder.find(FakeCell(self.sheet, "A1"))
		reads = self.sheet.Shapes.reads
		self.finder.find(FakeCell(self.sheet, "A2"))
		self.assertEqual(self.sheet.Shapes.reads, reads + 1)

	def test_emptyCellIsNamedByTheCellToItsRight(self):
		# The PRAE form's Richtigkeitsvermerk: box on the empty cell P42, text in Q42.
		self.sheet.texts[(42, 17)] = "Richtigkeitsvermerk: Dieser Beleg wird bei keinem anderen Fördergeber …"
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P42", value=1, row=42, column=16))
		self.assertEqual(self.finder.find(FakeCell(self.sheet, "P42")), (True, "Richtigkeitsvermerk"))

	def test_rightOfAMergedAreaIsAfterItsLastColumn(self):
		self.sheet.texts[(9, 24)] = "Masseur:in"
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P9:W9", row=9, column=16, width=8))
		self.assertEqual(self.finder.find(FakeCell(self.sheet, "P9:W9")), (False, "Masseur:in"))

	def test_emptyNeighbourFallsBackToTheAlternativeText(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P42", name="Richtigkeitsvermerk", row=42, column=16))
		self.assertEqual(self.finder.find(FakeCell(self.sheet, "P42")), (False, "Richtigkeitsvermerk"))

	def test_labelledCellReadsNoNeighbour(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "B9", value=1, row=9, column=2))
		self.assertEqual(self.finder.find(FakeCell(self.sheet, "B9"), needsName=False), (True, ""))
		self.assertEqual(self.sheet.cellReads, 0)

	def test_rescansWhenABoxIsAdded(self):
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "A1"))
		self.assertIsNone(self.finder.find(FakeCell(self.sheet, "A2")))
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "A2", value=1))
		self.assertTrue(self.finder.find(FakeCell(self.sheet, "A2"))[0])


class ToggleTests(unittest.TestCase):
	def setUp(self):
		self.sheet = FakeSheet()
		self.finder = checkboxState.CheckboxFinder()

	def test_ticksAndUnticks(self):
		shape = FakeShape(self.sheet, "P9:W9", name="Übungsleiter:in")
		self.sheet.Shapes.items.append(shape)
		cell = FakeCell(self.sheet, "P9:W9")
		self.assertEqual(self.finder.toggle(cell), (True, "Übungsleiter:in"))
		self.assertEqual(shape.OLEFormat.Object.Value, 1)
		self.assertEqual(self.finder.toggle(cell), (False, "Übungsleiter:in"))
		self.assertEqual(shape.OLEFormat.Object.Value, -4146)

	def test_namesTheEmptyCellsBoxAfterTicking(self):
		self.sheet.texts[(42, 17)] = "Richtigkeitsvermerk: Dieser Beleg …"
		self.sheet.Shapes.items.append(FakeShape(self.sheet, "P42", row=42, column=16))
		self.assertEqual(self.finder.toggle(FakeCell(self.sheet, "P42")), (True, "Richtigkeitsvermerk"))

	def test_mixedBoxBecomesTicked(self):
		shape = FakeShape(self.sheet, "A26", value=2)
		self.sheet.Shapes.items.append(shape)
		self.assertTrue(self.finder.toggle(FakeCell(self.sheet, "A26"))[0])

	def test_cellWithoutCheckboxChangesNothing(self):
		shape = FakeShape(self.sheet, "A26", value=1)
		self.sheet.Shapes.items.append(shape)
		self.assertIsNone(self.finder.toggle(FakeCell(self.sheet, "A1")))
		self.assertEqual(shape.OLEFormat.Object.Value, 1)

	def test_reportsWhatExcelNowHas(self):
		class StuckControl(FakeControl):
			@property
			def Value(self):
				return 1

			@Value.setter
			def Value(self, value):
				pass

		shape = FakeShape(self.sheet, "A26")
		shape.OLEFormat.Object = StuckControl(1)
		self.sheet.Shapes.items.append(shape)
		self.assertTrue(self.finder.toggle(FakeCell(self.sheet, "A26"))[0])


if __name__ == "__main__":
	unittest.main()
