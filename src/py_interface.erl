%%%-------------------------------------------------------------------
%%% @author Leon Wehmeier
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. Jun 2018 17:18
%%%-------------------------------------------------------------------
-module(py_interface).
-author("Leon Wehmeier").

%% API
-export([start/0, stop/0, subscribe/2, publish/3, startPublisher/0]).

-define(PYNODE, 'py@rpi3').
-define(GRISPNODE, 'helloworld@grisp_board').
-define(GRISPPROCESS, grisp_bridge).
-define(PYPROCESS, pyBridge).

start() ->
  connect_to_remote_node(),
  setupSubscribers(),
  startPublisher().

stop() ->
  {?PYPROCESS,?PYNODE} ! {self(), stop},
  erlBridge ! stop,
  erlBridgePub ! stop,
  unregister(erlBridge).

subscribe(MsgFormat, Topic) ->
  {?PYPROCESS,?PYNODE} ! {self(), subscribe, MsgFormat, Topic},
  receive
    {_, {ok, Topic}} -> ok;
    {_, {err, already_subscribed}} -> ok;
    {_, {err, unknown_message_type, Type}} -> {err, unknown_message_type, Type};
    Msg -> {err, unknown_response, Msg}
  after 1500 ->
    exit({pyBridge_timeout, subscribe, Topic})
  end.
publish(MsgFormat, Topic, Data) ->
  {?PYPROCESS,?PYNODE} ! {self(), publish, MsgFormat, Topic, Data},
  receive
    {_, {ok, Topic}} -> ok;
    {_, {err, unknown_message_type, Type}} -> {err, unknown_message_type, Type};
    Msg -> {err, unknown_response, Msg}
  after 5500 ->
    exit({pyBridge_timeout, publish, Topic})
  end.
publish_ff(MsgFormat, Topic, Data) ->
	{?PYPROCESS,?PYNODE} ! {self(), publish, MsgFormat, Topic, Data}.
call_grisp_handler({Module, Function}, Data) ->
  rpc:call(?GRISPNODE, Module, Function, Data).
% case erlang:function_exported(Module, Function, 1) of
% true -> [A1] = Data, Module:Function(A1);
% false -> case erlang:function_exported(Module, Function, 1) of
%   true -> [A1, A2] = Data, Module:Function(A1, A2);
%   false -> [A1, A2, A3] = Data, Module:Function(A1, A2, A3).
%   end
%end.

connect_to_grisp() ->
  net_adm:ping(?GRISPNODE),
  net_adm:ping(?GRISPNODE),
  net_adm:ping(?GRISPNODE),% ping a few times, on grisp the initial connection attempt can time out
  ConnectedRemoteNode = net_kernel:connect_node(?GRISPNODE),
  ConnectedRemoteNode.

connect_to_remote_node() ->
  ConnectedRemoteNode = net_kernel:connect_node(?PYNODE),
  case ConnectedRemoteNode of
    true ->
      GrispConnected = connect_to_grisp(),
      case GrispConnected of
        true ->
          Pid = spawn(fun loop/0),
          erlang:register(erlBridge, Pid);
        false->
          io:format("Could not connect to grisp node, is it running? ~n"),
          false
      end;
    false ->
      io:format("Could not connect to Python node, is it running? ~n"),
      false
  end.

setupSubscribers()->
  subscribe(int16, "platform/speed"),
  timer:sleep(100),
  subscribe(int16, "platform/direction"),
  timer:sleep(100),
  subscribe(int16, "platform/angular"),
  timer:sleep(100),
  subscribe(vector3, "platform/combined"),
  timer:sleep(100),
  subscribe(int16, "platform/go"),
  timer:sleep(100),
  subscribe(int16, "led/blue"),
  timer:sleep(100),
  subscribe(int16, "led/off"),
  timer:sleep(100).

startPublisher()->
  Pid = spawn(fun publishLoop/0),
  erlang:register(erlBridgePub, Pid).

publishLoop()->
  receive
    {stop} -> io:format("shutting down publisher loop~n")
  after 250 ->
    %Led1r = call_grisp_handler({grisp_gpio, get},[led1_r]),
    %Led1g = call_grisp_handler({grisp_gpio, get},[led1_g]),
    %Led1b = call_grisp_handler({grisp_gpio, get},[led1_b]),
    %Led2r = call_grisp_handler({grisp_gpio, get},[led2_r]),
    %Led2g = call_grisp_handler({grisp_gpio, get},[led2_g]),
    %Led2b = call_grisp_handler({grisp_gpio, get},[led2_b]),
    %publish(bool, "led2/b", Led2b),
    %publish(bool, "led2/g", Led2g),
    %publish(bool, "led2/r", Led2r),
    %publish(bool, "led1/b", Led1b),
    %publish(bool, "led1/r", Led1r),
    %publish(bool, "led1/g", Led1g),
    %Distance = call_grisp_handler({gen_server, call},[vl6180x, get_distance]),
    Current1 = call_grisp_handler({gen_server, call},[ina219_40, get_current]),
    Current2 = call_grisp_handler({gen_server, call},[ina219_44, get_current]),
    Voltage1 = call_grisp_handler({gen_server, call},[ina219_40, get_voltage]),
    Voltage2 = call_grisp_handler({gen_server, call},[ina219_44, get_voltage]),
    %{AX, AY, AZ} = call_grisp_handler({gen_server, call},[pmod_nav2, getAcc]),
    {GX, GY, GZ} = call_grisp_handler({gen_server, call},[pmod_nav2, getGy]),
    %publish(int16, "/distance", Distance),
    publish_ff(float32, "/batteries/drive/current", Current1),
    publish_ff(float32, "/batteries/electronics/current", Current2),
    publish_ff(float32, "/batteries/drive/voltage", Voltage1),
    publish_ff(float32, "/batteries/electronics/voltage", Voltage2),
    %publish(float32, "/acceleration/x", AX),
    %publish(float32, "/acceleration/y", AY),
    %publish(float32, "/acceleration/z", AZ),
    publish_ff(float32, "/gyro/x", GX),
    publish_ff(float32, "/gyro/y", GY),
    publish_ff(float32, "/gyro/z", GZ),
    publishLoop()
  end.

loop() ->
  receive
    stop ->
      io:format("Stopping loop~n");
    {Remote, test} ->
      io:format("received message test~n"),
      {?PYPROCESS,?PYNODE} ! {self(), testReply},
      loop();
    {Remote, {acc, {X, Y, Z}}} ->
      io:format("X: ~p, Y: ~p, Z: ~p~n", [X, Y, Z]),
      loop();
    {Remote, {push, "platform/speed", Speed}} ->
      io:format("Setting speed to ~p~n", [Speed]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {speed, Speed}]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {apply, true}]),
      loop();
    {Remote, {push, "platform/direction", Angle}} ->
      io:format("Setting direction to ~p~n", [Angle]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {direction, Angle}]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {apply, true}]),
      loop();
    {Remote, {push, "platform/combined", {X, Y, Theta}}} ->
      io:format("Update all (X, Y, Theta) ~p ~p ~p ~n", [X, Y, Theta]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {xyTheta, {X, Y, Theta}}]),
      loop();
    {Remote, {push, "platform/angular", Theta}} ->
      io:format("Setting theta to ~p~n", [Theta]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {theta, Theta}]),
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {apply, true}]),
      loop();
    {Remote, {push, "platform/go", 1}} ->
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {go, true}]),
      loop();
    {Remote, {push, "platform/go", 0}} ->
      ok = call_grisp_handler({gen_server, call}, [motioncontroller, {stop, true}]),
      loop();
    {Remote, {push, "led/red", ID}} ->
      io:format("Setting led ~p to on~n", [ID]),
      ok = call_grisp_handler({grisp_led, color}, [ID, red]),
      loop();
    {Remote, {push, "led/green", ID}} ->
      io:format("Setting led ~p to on~n", [ID]),
      ok = call_grisp_handler({grisp_led, color}, [ID, green]),
      loop();
    {Remote, {push, "led/off", ID}} ->
      io:format("Setting led ~p to on~n", [ID]),
      ok = call_grisp_handler({grisp_led, off}, [ID]),
      loop();
    {Remote, {push, "grisp", String}} ->
      io:format("Received from ~p on topic ~s: ~s~n", [Remote, "grisp", String]),
      ok = call_grisp_handler({io, format}, ["executed on grisp~n"]),
      loop();
    {Remote, {push, Topic, String}} ->
      io:format("Received from ~p on topic ~s: ~s~n", [Remote, Topic, String]),
      loop()
  end.
