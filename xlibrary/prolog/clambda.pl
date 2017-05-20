/*  Part of Extended Libraries for SWI-Prolog

    Author:        Edison Mera Menendez
    E-mail:        efmera@gmail.com
    WWW:           https://github.com/edisonm/xlibrary
    Copyright (C): 2014, Process Design Center, Breda, The Netherlands.
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

:- module(clambda, [op(201,xfx,+\)]).

/** <module> Lambda expressions

This library is semantically equivalent to the lambda library implemented by
Ulrich Neumerkel, but it performs static expansion of the expressions to improve
performance.

*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(occurs)).
:- use_module(library(compound_expand)).

remove_hats(^(H, G0), G) -->
    [H], !,
    remove_hats(G0, G).
remove_hats(G, G) --> [].

remove_hats(G0, G, EL) :-
    remove_hats(G0, G1, EL, T),
    '$expand':extend_arg_pos(G1, _, T, G, _).

cgoal_args(G0, G, AL, EL) :-
    G0 =.. [F|Args],
    cgoal_args(F, Args, G, Fr, EL),
    term_variables(Fr, AL).

cgoal_args(\,  [G1|EL],    G, [], EL) :- remove_hats(G1, G, EL).
cgoal_args(+\, [Fr,G1|EL], G, Fr, EL) :- remove_hats(G1, G, EL).

singleton(T, Name=V) :-
    occurrences_of_var(V, T, 1),
    \+ atom_concat('_', _, Name).

have_name(VarL, _=Value) :-
    member(Var, VarL),
    Var==Value, !.

bind_name(Name=_, Name).

check_singletons(Goal, Term) :-
    term_variables(Term, VarL),
    ( b_getval('$variable_names', Bindings)
    ->true
    ; Bindings = []
    ),
    include(have_name(VarL), Bindings, VarN),
    include(singleton(Term), VarN, VarSN),
    ( VarSN \= []
    ->maplist(bind_name, VarSN, Names),
      print_message(warning, local_variables_outside(Names, Goal, Bindings))
    ; true
    ).

prolog:message(local_variables_outside(Names, Goal, Bindings)) -->
    [ 'Local variables ~w should not occurs outside lambda expression: ~W'
    -[Names, Goal, [variable_names(Bindings)]] ].

lambdaize_args(G, A0, M, VL, Ex, A) :-
    check_singletons(G, h(VL, Ex, A0 )),
    ( ( Ex==[]
      ; '$member'(E1, Ex),
        '$member'(E2, VL),
        E1==E2
      )
    ->'$expand':wrap_meta_arguments(A0, M, VL, Ex, A)
    ; '$expand':remove_arg_pos(A0, _, M, VL, Ex, A, _)
    ).

goal_expansion(G0, G) :-
    callable(G0),
    cgoal_args(G0, G1, AL, EL),
    '$current_source_module'(M),
    expand_goal(G1, G2),
    lambdaize_args(G0, G2, M, AL, EL, G3),
    % '$expand':wrap_meta_arguments(G2, M, AL, EL, G3), % Use this to debug
    G3 =.. [AuxName|VL],
    append(VL, EL, AV),
    G =.. [AuxName|AV].
