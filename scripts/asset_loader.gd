class_name AssetLoader
## Dynamic texture loader supporting both imported resources and runtime direct images.

static func load_texture(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Texture2D:
			return res
	var global_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global_path):
		var img := Image.load_from_file(global_path)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	elif FileAccess.file_exists(res_path):
		var img := Image.load_from_file(res_path)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null
