extends Control
## Reusable settings panel (used by the pause menu and, later, the main menu).

signal back_pressed

@onready var sens_slider: HSlider = $Center/Panel/Margin/VBox/Grid/SensSlider
@onready var sens_value: Label = $Center/Panel/Margin/VBox/Grid/SensValue
@onready var fov_slider: HSlider = $Center/Panel/Margin/VBox/Grid/FovSlider
@onready var fov_value: Label = $Center/Panel/Margin/VBox/Grid/FovValue
@onready var vol_slider: HSlider = $Center/Panel/Margin/VBox/Grid/VolSlider
@onready var vol_value: Label = $Center/Panel/Margin/VBox/Grid/VolValue
@onready var back_button: Button = $Center/Panel/Margin/VBox/BackButton

func _ready() -> void:
	sens_slider.value_changed.connect(_on_changed)
	fov_slider.value_changed.connect(_on_changed)
	vol_slider.value_changed.connect(_on_changed)
	back_button.pressed.connect(_on_back)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()
		back_button.grab_focus()

## Load the current values into the sliders without re-triggering changes.
func _refresh() -> void:
	sens_slider.set_value_no_signal(Settings.mouse_sensitivity)
	fov_slider.set_value_no_signal(Settings.fov)
	vol_slider.set_value_no_signal(Settings.master_volume)
	_update_labels()

func _on_changed(_value: float) -> void:
	Settings.mouse_sensitivity = sens_slider.value
	Settings.fov = fov_slider.value
	Settings.master_volume = vol_slider.value
	Settings.apply()
	_update_labels()

func _update_labels() -> void:
	sens_value.text = "%.1fx" % sens_slider.value
	fov_value.text = "%d" % fov_slider.value
	vol_value.text = "%d%%" % roundi(vol_slider.value * 100.0)

func _on_back() -> void:
	Settings.save()
	back_pressed.emit()
