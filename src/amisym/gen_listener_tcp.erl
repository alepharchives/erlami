-module(gen_listener_tcp).
-behaviour(gen_server).

-export([behaviour_info/1]).

-export([
        start/3,
        start/4,
        start_link/3,
        start_link/4,
        stop/1
    ]).


-export([
        init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3
    ]).

-record(listener_state, {
        socket,
        acceptor,
        mfa
        }).


behaviour_info(callbacks) ->
    [
        {init, 1}
    ];

behaviour_info(_Other) ->
    undefined.


start_link(Name, Module, InitArgs, Options) ->
    gen_server:start_link(Name, ?MODULE, [{je_cb_module, Module} | InitArgs], Options).

start_link(Module, InitArgs, Options) ->
    gen_server:start_link(?MODULE, [{je_cb_module, Module} | InitArgs], Options).

start(Name, Module, InitArgs, Options) ->
    gen_server:start(Name, ?MODULE, [{je_cb_module, Module} | InitArgs], Options).

start(Module, InitArgs, Options) ->
    gen_server:start(?MODULE, [{je_cb_module, Module} | InitArgs], Options).

stop(Name) ->
    gen_server:cast(Name, stop).


% gen_server callbacks

init([{je_cb_module, Module} | InitArgs]) ->
    process_flag(trap_exit, true),

    case Module:init(InitArgs) of
        {ok, {Port, Options, Mfa}} ->
            {ok, ListenSocket} = gen_tcp:listen(Port, Options),

            error_logger:info_report([listening_started, {port, Port}, {lsock, ListenSocket} | Options]), 

            {ok, ListenerState} = create_acceptor(ListenSocket, Mfa),
            {ok, ListenerState};
        Other ->
            {stop, Other}
    end.


handle_call(Request, _From, ListenerState) ->
    {reply, {illegal, Request}, ListenerState}.

handle_cast(stop, ListenerState) ->
    {stop, normal, ListenerState};

handle_cast(_Request, ListenerState) ->
    {noreply, ListenerState}.

handle_info({inet_async, LSock, ARef, {ok, ClientSock}}, #listener_state{socket=LSock, acceptor=ARef}=ListenerState) ->
    error_logger:info_report([new_connection, {csock, ClientSock}, {lsock, LSock}, {async_ref, ARef}]),
    try
        patch_client_socket(ClientSock, LSock),
        {Module, Function, Args} = ListenerState#listener_state.mfa,
        NewArgs = [ClientSock | Args],

        error_logger:info_report([calling_handler, {module, Module}, {function, Function}, {args, NewArgs}]),
        {ok, Pid} = apply(Module, Function, NewArgs),

        error_logger:info_report([changing_controlling_socket, {oldpid, self()}, {newpid, Pid}]),
        ok = gen_tcp:controlling_process(ClientSock, Pid)
    catch
        Type:Exception -> 
            error_logger:error_report({Type, Exception}),
            gen_tcp:close(ClientSock)
    end,


    {ok, NewListenerState} = create_acceptor(ListenerState),
    {noreply, NewListenerState};

handle_info({inet_async, LSock, ARef, Error}, #listener_state{socket=LSock, acceptor=ARef}=ListenerState) ->
    error_logger:error_report([acceptor_error, {reason, Error}, {lsock, LSock}, {async_ref, ARef}]),
    {stop, Error, ListenerState};

handle_info(_Info, ListenerState) ->
    {noreply, ListenerState}.

terminate(Reason, ListenerState) ->
    error_logger:info_report([listener_terminating, {reason, Reason}]),
    gen_tcp:close(ListenerState#listener_state.socket),
    ok.

code_change(_OldVsn, ListenerState, _Extra) ->
    {noreply, ListenerState}.


% prim_inet imports
patch_client_socket(CSock, LSock) when is_port(CSock), is_port(LSock) ->
    {ok, Module} = inet_db:lookup_socket(LSock),
    true = inet_db:register_socket(CSock, Module),

    {ok, Opts} = prim_inet:getopts(LSock, [active, nodelay, keepalive, delay_send, priority, tos]),
    ok = prim_inet:setopts(CSock, Opts),
    ok.

create_acceptor(ListenerState) when is_record(ListenerState, listener_state) ->
    create_acceptor(ListenerState#listener_state.socket, ListenerState#listener_state.mfa).

create_acceptor(ListenSocket, Mfa) when is_port(ListenSocket) ->
    {ok, Ref} = prim_inet:async_accept(ListenSocket, -1), 

    error_logger:info_report(waiting_for_connection), 
    {ok, #listener_state{socket=ListenSocket, acceptor=Ref, mfa=Mfa}}.
