@tool
extends SceneTree

## Headless reproduction for ticket 01: does a stock Zed JSONC settings.json
## (leading `// Zed settings` header) produce the `MCP | JSON parse error on
## line 0` warning on the load-time read paths in the CURRENT tree?
##
## Run: Godot --headless --path test_project --script res://../.scratch/repro_zed_jsonc.gd
## (path adjusted at invocation). Prints REPRO_RESULT lines and quits.

const JsonStrategy := preload("res://addons/godot_ai/clients/_json_strategy.gd")
const ZedClient := preload("res://addons/godot_ai/clients/zed.gd")

func _init() -> void:
	var tmp := "user://repro_zed_stock.json"
	# Exactly what the ticket describes: Zed's stock `//` header + JSONC body.
	var body := "// Zed settings\n//\n// For information on how to configure Zed, see the Zed\n{\n\t\"theme\": \"One Dark\"\n}\n"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(body)
	f.close()
	var abs_path := ProjectSettings.globalize_path(tmp)

	var client := ZedClient.new()
	client.path_template = {"darwin": abs_path, "linux": abs_path, "windows": abs_path, "unix": abs_path}

	print("REPRO_RESULT descriptor config_allows_comments=", client.config_allows_comments,
		" automatic_config_edits=", client.automatic_config_edits)

	# Load-time read path 1: status refresh.
	var status = JsonStrategy.check_status_details(client, "godot-ai", "http://127.0.0.1:8000/mcp", {})
	print("REPRO_RESULT check_status_details status=", status.get("status"),
		" error_msg=", JSON.stringify(String(status.get("error_msg", ""))))

	# Load-time read path 2: manual "Run this manually" target inspection.
	var manual = JsonStrategy.manual_target_details(client, "godot-ai", abs_path)
	print("REPRO_RESULT manual_target_details ok=", manual.get("ok", false),
		" error=", JSON.stringify(str(manual.get("error", ""))))

	# Direct read WITHOUT the flag (what configure()'s :29 read would do) — this
	# is the strict-parse path that WOULD warn, shown for contrast. configure()
	# itself is gated out for Zed, but this proves the strict path still warns.
	var strict = JsonStrategy._read_or_init(abs_path)
	print("REPRO_RESULT strict_read(no flag) ok=", strict.get("ok", false),
		" error=", JSON.stringify(str(strict.get("error", ""))))

	# Read WITH the flag (what the load-time paths actually do).
	var tolerant = JsonStrategy._read_or_init(abs_path, true)
	print("REPRO_RESULT tolerant_read(flag) ok=", tolerant.get("ok", false),
		" error=", JSON.stringify(str(tolerant.get("error", ""))))

	print("REPRO_RESULT done")
	quit()
