# Reports the state of an Excel form checkbox with the cell it sits on.
#
# NVDA's cell navigation only gets the cell's text; the checkbox floats above the
# cell. So this asks Excel for the checkbox on each cell. NVDA reads Excel in two
# ways, and each has its own cell class and property for the text.

import api
import controlTypes
import globalPluginHandler
import ui
from logHandler import log
from NVDAObjects.UIA.excel import ExcelCell as UIAExcelCell
from NVDAObjects.window.excel import ExcelBase
from NVDAObjects.window.excel import ExcelCell as ObjectModelExcelCell
from scriptHandler import script

from . import checkboxState

_finder = checkboxState.CheckboxFinder()


def _withCheckbox(text, cell):
	"""text, with the state added if cell has a checkbox. Reporting must never fail."""
	try:
		found = _finder.find(cell)
	except Exception:
		log.debugWarning("Could not read Excel checkboxes", exc_info=True)
		return text
	if found is None:
		return text
	isChecked, controlName = found
	return checkboxState.labelWithMark(text, isChecked, controlName)


class ObjectModelCheckboxCell(ObjectModelExcelCell):
	def _get_name(self):
		return _withCheckbox(super().name, self.excelCellObject)

	def activeExcelCell(self):
		return self.excelCellObject


class UIACheckboxCell(UIAExcelCell):
	def _get_value(self):
		value = super().value
		if value is None or controlTypes.State.FOCUSED not in self.states:
			return value
		cell = self.activeExcelCell()
		return value if cell is None else _withCheckbox(value, cell)

	def activeExcelCell(self):
		window = ExcelBase.excelWindowObjectFromWindow(self.windowHandle)
		return window.ActiveCell if window else None


class GlobalPlugin(globalPluginHandler.GlobalPlugin):
	def chooseNVDAObjectOverlayClasses(self, obj, clsList):
		if isinstance(obj, ObjectModelExcelCell) or ObjectModelExcelCell in clsList:
			clsList.insert(0, ObjectModelCheckboxCell)
		elif UIAExcelCell in clsList:
			clsList.insert(0, UIACheckboxCell)

	@script(
		description="Kreuzt das Kontrollkästchen in der aktuellen Zelle an oder entfernt das Kreuz",
		category="Excel-Kontrollkästchen",
		gesture="kb:NVDA+alt+x",
	)
	def script_toggleCheckbox(self, gesture):
		focus = api.getFocusObject()
		if not isinstance(focus, (ObjectModelCheckboxCell, UIACheckboxCell)):
			gesture.send()
			return
		try:
			cell = focus.activeExcelCell()
			toggled = _finder.toggle(cell) if cell is not None else None
			text = cell.Text if toggled else ""
		except Exception:
			log.debugWarning("Could not change an Excel checkbox", exc_info=True)
			ui.message("Kontrollkästchen konnte nicht geändert werden")
			return
		if toggled is None:
			ui.message("Kein Kontrollkästchen in dieser Zelle")
			return
		isChecked, controlName = toggled
		ui.message(checkboxState.labelWithMark(text, isChecked, controlName))
