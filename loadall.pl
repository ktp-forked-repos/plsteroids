:- [plsteroids].
:- use_module(library(apply_macros)). % Load it proactively
:- use_module(pldoc(doc_modes)).
:- [library(checkers)].
:- [checkers(check_abstract_domains)].
:- [loadpacks].

:- set_prolog_flag(autoload, false).
:- loadpacks(consult).
:- set_prolog_flag(autoload, true).
:- [library(ws_source)].
