-module(test_amisym_eventbus).
-include_lib("eunit/include/eunit.hrl").


amisym_eventbus_init_test() ->
    {ok, Pid} = amisym_eventbus:start_link(),
    ?assertEqual(is_pid(Pid), true).

amisym_eventbus_connect_test() ->
    amisym_eventbus:start_link(),
    ?assertEqual({ok, connected}, amisym_eventbus:connect()).
