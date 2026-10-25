extends Node3D
## Platzhalter-Spielfigur: Kapsel mit drehendem Aufzieh-Schlüssel und Namensschild.

var body: MeshInstance3D
var key: MeshInstance3D
var body_mat := StandardMaterial3D.new()


func setup(color: Color, label: String, highlight := false) -> void:
	body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 0.9
	body.mesh = capsule
	body.position.y = 0.45
	body_mat.albedo_color = color
	body.material_override = body_mat
	add_child(body)

	key = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.12, 0.05)
	key.mesh = box
	key.position = Vector3(0, 0.6, -0.34)
	var key_mat := StandardMaterial3D.new()
	key_mat.albedo_color = Color(0.85, 0.7, 0.3)
	key_mat.metallic = 0.8
	key.material_override = key_mat
	add_child(key)

	var tag := Label3D.new()
	tag.text = label
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 1.25
	tag.font_size = 48
	tag.pixel_size = 0.006
	tag.outline_size = 10
	tag.modulate = color.lightened(0.2)
	tag.no_depth_test = true
	add_child(tag)

	if highlight:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.38
		torus.outer_radius = 0.48
		ring.mesh = torus
		ring.position.y = 0.05
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color.WHITE
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = ring_mat
		add_child(ring)


## Ausgeschiedene Spieler werden im Minigame halb durchsichtig.
func set_ghost() -> void:
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.albedo_color.a = 0.35
	key.visible = false


func _process(delta: float) -> void:
	if key:
		key.rotate_z(delta * 4.0)
