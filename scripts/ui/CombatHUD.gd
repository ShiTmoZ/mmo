## scripts/ui/CombatHUD.gd
## Minimalist tactical HUD: local vitals, target frame, cast bars, action bar.
## Attach to CombatHUD scene root (CanvasLayer).
class_name CombatHUD
extends CanvasLayer

const GameData = preload("res://scripts/core/GameData.gd")

# ---------------------------------------------------------------------------
# Node references — matched to CombatHUD.tscn hierarchy
# ---------------------------------------------------------------------------
# Local player vitals
@onready var _health_bar: ProgressBar        = $VitalsPanel/VBox/HealthBar
@onready var _mana_bar: ProgressBar          = $VitalsPanel/VBox/ManaBar
@onready var _stamina_bar: ProgressBar       = $VitalsPanel/VBox/StaminaBar
@onready var _stagger_bar: ProgressBar       = $VitalsPanel/VBox/StaggerBar
@onready var _player_name_label: Label       = $VitalsPanel/VBox/PlayerNameLabel

# Self cast bar
@onready var _self_cast_panel: PanelContainer    = $SelfCastPanel
@onready var _self_cast_bar: ProgressBar         = $SelfCastPanel/CastVBox/CastBar
@onready var _self_cast_spell_label: Label       = $SelfCastPanel/CastVBox/SpellNameLabel
@onready var _self_cast_interrupt_label: Label   = $SelfCastPanel/CastVBox/InterruptedLabel

# Target frame
@onready var _target_frame: PanelContainer       = $TargetFrame
@onready var _target_name_label: Label           = $TargetFrame/TargetVBox/TargetNameLabel
@onready var _target_health_bar: ProgressBar     = $TargetFrame/TargetVBox/TargetHealthBar
@onready var _target_cast_panel: PanelContainer  = $TargetFrame/TargetVBox/TargetCastPanel
@onready var _target_cast_bar: ProgressBar       = $TargetFrame/TargetVBox/TargetCastPanel/TCastVBox/TargetCastBar
@onready var _target_cast_label: Label           = $TargetFrame/TargetVBox/TargetCastPanel/TCastVBox/TargetCastLabel

# Action bar
@onready var _slot_1_label: Label    = $ActionBar/Slot1/SlotVBox/SpellLabel
@onready var _slot_1_cd: Label       = $ActionBar/Slot1/SlotVBox/CooldownLabel
@onready var _slot_2_label: Label    = $ActionBar/Slot2/SlotVBox/SpellLabel
@onready var _slot_2_cd: Label       = $ActionBar/Slot2/SlotVBox/CooldownLabel
@onready var _slot_3_label: Label    = $ActionBar/Slot3/SlotVBox/SpellLabel
@onready var _slot_3_cd: Label       = $ActionBar/Slot3/SlotVBox/CooldownLabel

# Slot overlay panels for greying out on cooldown
@onready var _slot_1_overlay: ColorRect = $ActionBar/Slot1/CooldownOverlay
@onready var _slot_2_overlay: ColorRect = $ActionBar/Slot2/CooldownOverlay
@onready var _slot_3_overlay: ColorRect = $ActionBar/Slot3/CooldownOverlay

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _player: Node                     = null
var _target: Node                     = null
var _cast_system: CastSystem          = null
var _interrupt_flash_timer: float     = 0.0
const _INTERRUPT_FLASH_DURATION: float = 2.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_self_cast_panel.hide()
	_target_frame.hide()
	_self_cast_interrupt_label.hide()
	_target_cast_panel.hide()

func init(player: Node) -> void:
	_player     = player
	_cast_system = player.get_cast_system() if player.has_method("get_cast_system") else null
	_player_name_label.text = player.display_name if "display_name" in player else "You"
	_populate_action_bar()
	update_vitals()

func _process(delta: float) -> void:
	if _player == null:
		return

	# Interrupt flash tick
	if _interrupt_flash_timer > 0.0:
		_interrupt_flash_timer -= delta
		if _interrupt_flash_timer <= 0.0:
			_self_cast_interrupt_label.hide()
			_self_cast_panel.hide()

	# Update self cast bar
	if _cast_system and _cast_system.is_casting():
		_self_cast_panel.show()
		_self_cast_bar.value = _cast_system.get_cast_progress() * 100.0
		var spell_id: int = _cast_system.get_current_spell_id()
		var spell = GameData.get_spell(spell_id)
		_self_cast_spell_label.text = spell.display_name if spell else "Casting..."
	elif _interrupt_flash_timer <= 0.0:
		_self_cast_panel.hide()

	# Update target frame
	if _target != null and is_instance_valid(_target):
		_target_frame.show()
		var t_health: float = _target.get_health() if _target.has_method("get_health") else 0.0
		_target_health_bar.value = (t_health / GameData.MAX_HEALTH) * 100.0

		# Target cast bar
		if _target.has_method("get_cast_system"):
			var t_cs: CastSystem = _target.get_cast_system() as CastSystem
			if t_cs and t_cs.is_casting():
				_target_cast_panel.show()
				_target_cast_bar.value = t_cs.get_cast_progress() * 100.0
				var t_spell_id: int = t_cs.get_current_spell_id()
				var t_spell = GameData.get_spell(t_spell_id)
				_target_cast_label.text = t_spell.display_name if t_spell else "Casting"
			else:
				_target_cast_panel.hide()
	else:
		_target_frame.hide()

	# Action bar cooldown overlays
	_update_action_slot_cooldown(0, _player.spell_slot_1 if "spell_slot_1" in _player else 1)
	_update_action_slot_cooldown(1, _player.spell_slot_2 if "spell_slot_2" in _player else 2)
	_update_action_slot_cooldown(2, _player.spell_slot_3 if "spell_slot_3" in _player else 3)

# ---------------------------------------------------------------------------
# Public callbacks (called from Player)
# ---------------------------------------------------------------------------
func update_vitals() -> void:
	if _player == null:
		return
	_health_bar.value  = (_player.get_health()   / GameData.MAX_HEALTH)   * 100.0
	_mana_bar.value    = (_player.get_mana()     / GameData.MAX_MANA)     * 100.0
	_stamina_bar.value = (_player.get_stamina()  / GameData.MAX_STAMINA)  * 100.0
	_stagger_bar.value = (_player.get_stagger()  / GameData.MAX_STAGGER)  * 100.0

func set_target(target: Node) -> void:
	_target = target
	if target != null:
		_target_name_label.text = target.display_name if "display_name" in target else "Enemy"
		_target_frame.show()
	else:
		_target_frame.hide()

func on_cast_started(spell_id: int, cast_time: float) -> void:
	var spell = GameData.get_spell(spell_id)
	_self_cast_panel.show()
	_self_cast_bar.value = 0.0
	_self_cast_spell_label.text = spell.display_name if spell else "Casting..."
	_self_cast_interrupt_label.hide()

func on_cast_completed(_spell_id: int) -> void:
	_self_cast_panel.hide()

func on_cast_interrupted(_spell_id: int) -> void:
	_self_cast_panel.show()
	_self_cast_bar.value = 0.0
	_self_cast_spell_label.text = ""
	_self_cast_interrupt_label.text = "INTERRUPTED!"
	_self_cast_interrupt_label.show()
	# Flash red: modulate the panel
	_self_cast_panel.modulate = Color(1.0, 0.2, 0.2, 1.0)
	var tween: Tween = create_tween()
	tween.tween_property(_self_cast_panel, "modulate", Color.WHITE, 0.5)
	_interrupt_flash_timer = _INTERRUPT_FLASH_DURATION

func on_cast_cancelled() -> void:
	_self_cast_panel.hide()
	_self_cast_interrupt_label.hide()

func on_player_died() -> void:
	# Optionally show death overlay — simple label for now
	push_warning("CombatHUD: Local player died")

# ---------------------------------------------------------------------------
# Action bar
# ---------------------------------------------------------------------------
func _populate_action_bar() -> void:
	if _player == null:
		return
	_set_slot_spell(0, _player.spell_slot_1 if "spell_slot_1" in _player else 1)
	_set_slot_spell(1, _player.spell_slot_2 if "spell_slot_2" in _player else 2)
	_set_slot_spell(2, _player.spell_slot_3 if "spell_slot_3" in _player else 6)

func _set_slot_spell(slot_index: int, spell_id: int) -> void:
	var spell = GameData.get_spell(spell_id)
	var label: Label
	match slot_index:
		0: label = _slot_1_label
		1: label = _slot_2_label
		2: label = _slot_3_label
		_: return
	label.text = spell.display_name if spell else "—"

func _update_action_slot_cooldown(slot_index: int, spell_id: int) -> void:
	if _cast_system == null:
		return
	var cd_label: Label
	var overlay: ColorRect
	match slot_index:
		0:
			cd_label = _slot_1_cd
			overlay  = _slot_1_overlay
		1:
			cd_label = _slot_2_cd
			overlay  = _slot_2_overlay
		2:
			cd_label = _slot_3_cd
			overlay  = _slot_3_overlay
		_:
			return

	if _cast_system.is_on_cooldown(spell_id):
		var remaining: float = _cast_system.get_cooldown_remaining(spell_id)
		cd_label.text = "%.1fs" % remaining
		overlay.show()
	else:
		cd_label.text = ""
		overlay.hide()
