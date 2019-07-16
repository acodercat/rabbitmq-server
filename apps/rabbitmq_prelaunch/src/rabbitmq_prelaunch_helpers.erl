-module(rabbitmq_prelaunch_helpers).

-export([mkdir_p/1,
         exit/1]).

mkdir_p(Path) ->
    [Root | Components] = filename:split(Path),
    mkdir_p(Root, Components).

mkdir_p(Parent, [Component | Rest]) ->
    Dir = filename:join(Parent, Component),
    case file:make_dir(Dir) of
        ok              -> mkdir_p(Dir, Rest);
        {error, eexist} -> mkdir_p(Dir, Rest);
        Error           -> Error
    end;
mkdir_p(_, []) ->
    ok.

exit(Reason) when is_atom(Reason) ->
    init:stop(reason_to_sysexit(Reason));
exit(Status) when is_integer(Status) ->
    init:stop(Status).

reason_to_sysexit(ex_ok)          -> 0;
reason_to_sysexit(ex_usage)       -> 64;
reason_to_sysexit(ex_dataerr)     -> 65;
reason_to_sysexit(ex_noinput)     -> 66;
reason_to_sysexit(ex_nouser)      -> 67;
reason_to_sysexit(ex_nohost)      -> 68;
reason_to_sysexit(ex_unavailable) -> 69;
reason_to_sysexit(ex_software)    -> 70;
reason_to_sysexit(ex_oserr)       -> 71;
reason_to_sysexit(ex_osfile)      -> 72;
reason_to_sysexit(ex_cantcreat)   -> 73;
reason_to_sysexit(ex_ioerr)       -> 74;
reason_to_sysexit(ex_tempfail)    -> 75;
reason_to_sysexit(ex_protocol)    -> 76;
reason_to_sysexit(ex_noperm)      -> 77;
reason_to_sysexit(ex_config)      -> 78.
