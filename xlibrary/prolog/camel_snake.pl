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

:- module(camel_snake, [camel_snake/2]).

:- use_module(library(ctypes)).

camel_snake(Camel, Snake) :-
    atom(Camel), !,
    atom_codes(Camel, CamelS),
    camel_snake_s(CamelS, SnakeS),
    atom_codes(Snake, SnakeS).
camel_snake(Camel, Snake) :-
    atom(Snake),
    atom_codes(Snake, SnakeS),
    camel_snake_s(CamelS, SnakeS),
    atom_codes(Camel, CamelS).

camel_snake_s([U|CL], [L|SL]) :-
    ( upper_lower(U, L)
    ->true
    ; U = L
    ),
    camel_snake_(CL, SL).
camel_snake_s([], []).

camel_snake_([U|CL], [0'_, L|SL]) :-
    upper_lower(U, L), !,
    camel_snake_(CL, SL).
camel_snake_([C|CL], [C|SL]) :-
    camel_snake_(CL, SL).
camel_snake_([], []).
