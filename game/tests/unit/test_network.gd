extends GutTest
## Server URL resolution for the Network autoload (native build, so no web query).

const RealTime := preload("res://tests/fixtures/real_time.gd")
var _saved_args: Dictionary


func test_websocket_buffers_handle_a_burst_larger_than_engine_defaults() -> void:
	var server := Network.create_transport()
	var client := Network.create_transport()
	var port := randi_range(20000, 40000)
	assert_eq(server.create_server(port), OK)
	assert_eq(client.create_client("ws://127.0.0.1:%d" % port), OK)
	var connected := await RealTime.wait_until(
		get_tree(),
		func() -> bool:
			server.poll()
			client.poll()
			return client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		5.0
	)
	assert_true(connected)
	if connected:
		var packet := PackedByteArray()
		packet.resize(4096)
		client.set_target_peer(1)
		for i: int in 64:
			packet.encode_u32(0, i)
			assert_eq(client.put_packet(packet), OK)
		var received: Array[int] = []
		assert_true(
			await RealTime.wait_until(
				get_tree(),
				func() -> bool:
					client.poll()
					server.poll()
					while server.get_available_packet_count() > 0:
						received.append(server.get_packet().decode_u32(0))
					return received.size() == 64,
				5.0
			)
		)
		for i: int in received.size():
			assert_eq(received[i], i)
	client.close()
	server.close()


func before_each() -> void:
	_saved_args = Network.args.duplicate()


func after_each() -> void:
	Network.args = _saved_args


func test_native_defaults_to_offline() -> void:
	Network.args = {}
	assert_eq(Network.resolve_server_url(), "")


func test_connect_arg_is_used() -> void:
	Network.args = {"connect": "ws://127.0.0.1:7777"}
	assert_eq(Network.resolve_server_url(), "ws://127.0.0.1:7777")


func test_offline_flag_wins() -> void:
	Network.args = {"connect": "ws://127.0.0.1:7777", "offline": ""}
	assert_eq(Network.resolve_server_url(), "")


func test_offline_keyword_means_offline() -> void:
	Network.args = {"connect": "offline"}
	assert_eq(Network.resolve_server_url(), "")


func test_project_default_server_is_configured() -> void:
	var url := str(ProjectSettings.get_setting(Network.DEFAULT_SERVER_SETTING, ""))
	assert_true(url.begins_with("wss://"), "web builds need a TLS WebSocket default")


func test_project_default_api_is_https() -> void:
	Network.args = {}
	assert_eq(Network.resolve_api_url(), "https://game.chrisbox.dev/api")


func test_api_arg_overrides_default() -> void:
	Network.args = {"api": "http://127.0.0.1:8080/api/"}
	assert_eq(Network.resolve_api_url(), "http://127.0.0.1:8080/api")


func test_unexported_builds_are_dev() -> void:
	assert_eq(Network.load_build_version(), "dev")
	assert_eq(Network.short_version("dev"), "dev")
	assert_eq(Network.short_version("6ae5b21013eedfda16ea"), "6ae5b21")
