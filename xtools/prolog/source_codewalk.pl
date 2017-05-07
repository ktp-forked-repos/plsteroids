/*  Part of Extended Tools for SWI-Prolog

    Author:        Edison Mera Menendez
    E-mail:        efmera@gmail.com
    WWW:           https://github.com/edisonm/xtools
    Copyright (C): 2017, Process Design Center, Breda, The Netherlands.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(source_codewalk,
          [source_codewalk/1]).

:- use_module(library(prolog_source)).
:- use_module(library(context_values)).
:- use_module(library(option_utils)).
:- use_module(library(extend_args)).

:- meta_predicate
    source_codewalk(:).

is_meta(on_trace).

source_codewalk(MOptionL) :-
    meta_options(is_meta, MOptionL, OptionL),
    setup_call_cleanup(prepare(Ref),
                       do_source_codewalk(OptionL),
                       cleanup(Ref)).

head_caller(MHead, M:Head) :-
    '$current_source_module'(CM),
    strip_module(CM:MHead, M, Head).

determine_caller((Head   :-  _), Caller) :- !, head_caller(Head, Caller).
determine_caller((DHead --> _), Caller) :-
    !,
    extend_args(DHead, [_, _], Head),
    head_caller(Head, Caller).
determine_caller(Head, Caller) :- head_caller(Head, Caller).
determine_caller((:- Decl), Caller) :- decl_caller(Decl, Caller).

decl_caller(initialization(_), '<initialization>').
decl_caller(_,                 '<declaration>').

:- public
    true_3/3,
    do_goal_expansion/2,
    determine_caller/2.

prepare(p(TRef, GRef)) :-
    assertz((system:term_expansion(T, P, T, P) :-
                 determine_caller(T, Caller),
                 set_context_value(caller, Caller)), TRef),
    assertz((system:goal_expansion(G, P, _, _) :-
                 once(do_goal_expansion(G, P)), fail), GRef).

cleanup(p(TRef, GRef)) :-
    erase(TRef),
    erase(GRef).

true_3(_, _, _).

/*
true_3(Goal, Caller, From) :-
    print_message(information,
                  at_location(From, format("~w :- ~w", [Caller, Goal]))).
*/

do_goal_expansion(Goal, TermPos) :-
    prolog_load_context(source, File),
    ( TermPos \= none
    ->From = file_term_position(File, TermPos)
    ; prolog_load_context(term_position, Pos),
      stream_position_data(line_count, Pos, Line),
      From = file(File, Line, -1, _)
    ),
    current_context_value(on_trace, OnTrace),
    current_context_value(caller,   Caller),
    '$current_source_module'(M),
    call(OnTrace, M:Goal, Caller, From).

do_source_codewalk(OptionL1) :-
    foldl(select_option_default,
          [on_trace(OnTrace)  -true_3,
           variable_names(VNL)-VNL],
          OptionL1, OptionL2),
    option_allchk(M, File, FileMGen-OptionL2, true-OptionL),
    freeze(VNL, b_setval('$variable_names', VNL)),
    with_context_values(
        setup_call_cleanup(
            ( '$current_source_module'(OldM),
              freeze(M, '$set_source_module'(_, M))
            ),
            forall(FileMGen,
                   walk_source(File, [variable_names(VNL)|OptionL])),
            '$set_source_module'(_, OldM)),
        [on_trace],
        [OnTrace]).

walk_source(File, OptionL) :-
    setup_call_cleanup(
        prolog_open_source(File, In),
        fetch_term(In, OptionL),
        prolog_close_source(In)).

fetch_term(In, OptionL) :-
    repeat,
      prolog_read_source_term(In, Term, _Expanded, OptionL),
      Term == end_of_file,
    !.
