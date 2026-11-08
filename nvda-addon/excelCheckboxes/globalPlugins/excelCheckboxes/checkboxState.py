# Finds the Excel form checkbox on a cell and builds the text to report.
# Nothing here imports NVDA, so it can be tested without it.

import re

SHAPE_TYPE_FORM_CONTROL = 8
FORM_CONTROL_CHECKBOX = 1
VALUE_CHECKED = 1
VALUE_UNCHECKED = -4146

# The box many forms draw in Wingdings, which NVDA reads as the letter r.
_BOX_GLYPH = re.compile("^[r\uf072]\\s+")


def _label(cellText, controlName):
	# An empty cell uses the control's name.
	return _BOX_GLYPH.sub("", cellText or "", count=1).strip() or (controlName or "").strip()


def hasLabel(cellText):
	"""Whether the cell's own text names its checkbox, so no other name is needed."""
	return bool(_BOX_GLYPH.sub("", cellText or "", count=1).strip())


# A colon ending a phrase, not the one inside "Trainer:in".
_PHRASE_COLON = re.compile(":(?:\\s|$)")


def shortLabel(text):
	"""A neighbouring cell's text up to its colon: "Richtigkeitsvermerk: Dieser Beleg …" → "Richtigkeitsvermerk"."""
	text = (text or "").strip()
	return _PHRASE_COLON.split(text, maxsplit=1)[0].strip() or text


def labelWithMark(cellText, isChecked, controlName=""):
	"""The text for braille: "[X] Trainer:in"."""
	mark = "[X]" if isChecked else "[ ]"
	return f"{mark} {_label(cellText, controlName)}".rstrip()


def spokenLabel(cellText, isChecked, controlName=""):
	"""The text for speech: "Trainer:in ausgewählt"."""
	state = "ausgewählt" if isChecked else "nicht ausgewählt"
	return f"{_label(cellText, controlName)} {state}".strip()


def replaceInSpeech(speechSequence, marked, spoken):
	"""speechSequence with marked swapped for spoken. Speech commands stay as they are."""
	return [
		item.replace(marked, spoken) if isinstance(item, str) else item
		for item in speechSequence
	]


class CheckboxFinder:
	"""Maps cells to the checkboxes on them.

	Where the boxes are is cached per sheet, as reading every shape on each cell
	move would be slow. Their state is never cached, so it is always current.
	"""

	def __init__(self):
		self._sheetKey = None
		self._shapeIndexesByCell = {}

	def find(self, cell, needsName=True):
		"""Returns (isChecked, controlName) for the checkbox on cell, or None.

		controlName is only looked up when needsName is set, i.e. when the cell
		itself is empty: it is the text of the next cell to the right, up to its
		colon, or else the checkbox's alternative text.
		"""
		shape = self._shape(cell)
		if shape is None:
			return None
		isChecked = shape.OLEFormat.Object.Value == VALUE_CHECKED
		return isChecked, (_controlName(shape) if needsName else "")

	def toggle(self, cell, needsName=True):
		"""Ticks or unticks the checkbox on cell and returns its new (isChecked, controlName).

		The state comes back from the checkbox itself, so the report is what Excel
		now has. Returns None if cell has no checkbox.
		"""
		found = self.find(cell, needsName=False)
		if found is None:
			return None
		control = self._shape(cell).OLEFormat.Object
		control.Value = VALUE_UNCHECKED if found[0] else VALUE_CHECKED
		return self.find(cell, needsName)

	def _shape(self, cell):
		shapes = cell.Worksheet.Shapes
		count = shapes.Count
		if not count:
			return None
		sheetKey = (cell.Worksheet.Parent.FullName, cell.Worksheet.Name, count)
		if sheetKey != self._sheetKey:
			self._shapeIndexesByCell = self._indexCheckboxes(shapes, count)
			self._sheetKey = sheetKey
		index = self._shapeIndexesByCell.get(_cellKey(cell))
		return None if index is None else shapes.Item(index)

	@staticmethod
	def _indexCheckboxes(shapes, count):
		indexes = {}
		for index in range(1, count + 1):
			shape = shapes.Item(index)
			if shape.Type != SHAPE_TYPE_FORM_CONTROL or shape.FormControlType != FORM_CONTROL_CHECKBOX:
				continue
			indexes.setdefault(_cellKey(shape.TopLeftCell), index)
		return indexes


def _controlName(shape):
	# A box on an empty cell, like the Richtigkeitsvermerk on the PRAE form, is
	# labelled by the cell to its right.
	area = shape.TopLeftCell.MergeArea
	right = area.Worksheet.Cells(area.Row, area.Column + area.Columns.Count)
	return shortLabel(right.Text) or (shape.AlternativeText or "").strip()


def _cellKey(cell):
	# A merged label is reported at its first cell, while a box may start on any
	# cell of the merge, so both are compared by the whole merged area.
	return cell.MergeArea.Address(False, False)
