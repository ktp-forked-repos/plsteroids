/*

    Part of CLP(Q) (Constraint Logic Programming over Rationals)

    Author:        Leslie De Koninck
    E-mail:        Leslie.DeKoninck@cs.kuleuven.be
    WWW:           http://www.swi-prolog.org
		   http://www.ai.univie.ac.at/cgi-bin/tr-online?number+95-09
    Copyright (C): 2006, K.U. Leuven and
		   1992-1995, Austrian Research Institute for
		              Artificial Intelligence (OFAI),
			      Vienna, Austria

    This software is based on CLP(Q,R) by Christian Holzbaur for SICStus
    Prolog and distributed under the license details below with permission from
    all mentioned authors.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(clpcd_bv,
	[
	    allvars/2,
	    backsubst/4,
	    backsubst_delta/5,
	    basis_add/2,
	    dec_step/3,
	    deref/3,
	    deref_var/3,
	    detach_bounds/2,
	    detach_bounds_vlv/6,
	    determine_active_dec/1,
	    determine_active_inc/1,
	    export_binding/1,
	    inc_step/3,
	    intro_at/3,
	    iterate_dec/3,
	    lb/4,
	    pivot_a/5,
	    pivot/6,
	    rcbl_status/7,
	    reconsider/2,
	    same_class/2,
	    solve/2,
	    solve_ord_x/4,
	    ub/4,
	    unconstrained/4,
	    var_with_def_assign/3,
	    var_with_def_intern/5,
	    maximize/2,
	    minimize/2,
	    sup/3,
	    sup/5,
	    inf/3,
	    inf/5,
	    'solve_='/2,
	    'solve_<'/2,
	    'solve_=<'/2,
	    'solve_=\\='/2,
	    log_deref/5
	]).

:- use_module(library(ordsets)).
:- use_module(library(clpcd/class)).
:- use_module(library(clpcd/store)).
:- use_module(library(clpcd/domain_ops)).
:- use_module(library(clpcd/ordering)).
:- use_module(library(clpcd/bb)).
:- use_module(library(clpcd/ineq)).
:- use_module(library(clpcd/nf)).
:- use_module(library(clpcd/project)).

% For the rhs maint. the following events are important:
%
%	-) introduction of an indep var at active bound B
%	-) narrowing of active bound
%	-) swap active bound
%	-) pivot
%

% a variables bound (L/U) can have the states:
%
%	-) t_none	no bounds
%	-) t_l		inactive lower bound
%	-) t_u		inactive upper bound
%	-) t_L		active lower bound
%	-) t_U		active upper bound
%	-) t_lu		inactive lower and upper bound
%	-) t_Lu		active lower bound and inactive upper bound
%	-) t_lU		inactive lower bound and active upper bound

% ----------------------------------- deref -----------------------------------
%

% deref(CLP,Lin,Lind)
%
% Makes a linear equation of the form [v(I,[])|H] into a solvable linear
% equation.
% If the variables are new, they are initialized with the linear equation X=X.

deref(CLP,Lin,Lind) :-
	split(Lin,H,I),
	normalize_scalar(I,Nonvar),
	length(H,Len),
	log_deref(Len,CLP,H,[],Restd),
	add_linear_11(CLP, Nonvar, Restd, Lind).

% log_deref(Len,CLP,[Vs|VsTail],VsTail,Res)
%
% Logarithmically converts a linear equation in normal form ([v(_,_)|_]) into a
% linear equation in solver form ([I,R,K*X|_]). Res contains the result, Len is
% the length of the part to convert and [Vs|VsTail] is a difference list
% containing the equation in normal form.

log_deref(0,_,Vs,Vs,Lin) :-
	!,
	Lin = [0,0].
log_deref(1,C,[v(K,[X^1])|Vs],Vs,Lin) :-
	!,
	deref_var(C, X, Lx),
	mult_linear_factor(C, Lx, K, Lin).
log_deref(2,C,[v(Kx,[X^1]),v(Ky,[Y^1])|Vs],Vs,Lin) :-
	!,
	deref_var(C,X,Lx),
	deref_var(C,Y,Ly),
	add_linear_ff(C, Lx, Kx, Ly, Ky, Lin).
log_deref(N,C,V0,V2,Lin) :-
	P is N >> 1,
	Q is N - P,
	log_deref(P,C,V0,V1,Lp),
	log_deref(Q,C,V1,V2,Lq),
	add_linear_11(C, Lp, Lq, Lin).

% deref_var(CLP,X,Lin)
%
% Returns the equation of variable X. If X is a new variable, a new equation
% X = X is made.

deref_var(CLP,X,Lin) :-
	(   get_attr(X,clpcd_itf,Att)
	->  (   \+ arg(1,Att,CLP)
	    ->  throw(error(permission_error('mix CLPCD variables of',
		'different domains:',X),context(_)))
	    ;   arg(4,Att,lin(Lin))
	    ->  true
	    ;   setarg(2,Att,type(t_none)),
		setarg(3,Att,strictness(0)),
		Lin = [0,0,l(X*1,Ord)],
		setarg(4,Att,lin(Lin)),
		setarg(5,Att,order(Ord))
	    )
	;   Lin = [0,0,l(X*1,Ord)],
	    put_attr(X,clpcd_itf,t(CLP,type(t_none),strictness(0),
		lin(Lin),order(Ord),n,n,n,n,n,n))
	).

% TODO
%
%

var_with_def_assign(CLP,Var,Lin) :-
	Lin = [I,_|Hom],
	(   Hom = []
	->  % X=k
	    Var = I
	;   Hom = [l(V*K,_)|Cs]
	->  (   Cs = [],
		compare_d(CLP, =, K, 1),	% K =:= 1
		compare_d(CLP, =, 0, I)
	    ->	% X=Y
		Var = V
	    ;	% general case
		var_with_def_intern(t_none,CLP,Var,Lin,0)
	    )
	).

% var_with_def_intern(Type,CLP,Var,Lin,Strictness)
%
% Makes Lin the linear equation of new variable Var, makes all variables of
% Lin, and Var of the same class and bounds Var by type(Type) and
% strictness(Strictness)

var_with_def_intern(Type,CLP,Var,Lin,Strict) :-
	put_attr(Var,clpcd_itf,t(CLP,type(Type),strictness(Strict),lin(Lin),
	    order(_),n,n,n,n,n,n)),	% check uses
	Lin = [_,_|Hom],
	get_or_add_class(Var,Class),
	same_class(Hom,Class).

% -----------------------------------------------------------------------------

% export_binding(Lst)
%
% Binds variables X to Y where Lst contains elements of the form [X-Y].

export_binding([]).
export_binding([X-Y|Gs]) :-
	Y = X,
	export_binding(Gs).

% 'solve_='(CLP,Nf)
%
% Solves linear equation Nf = 0 where Nf is in normal form.

'solve_='(CLP,Nf) :-
	deref(CLP,Nf,Nfd),	% dereferences and turns Nf into solvable form Nfd
	solve(CLP,Nfd).

% 'solve_=\\='(CLP,Nf)
%
% Solves linear inequality Nf =\= 0 where Nf is in normal form.

'solve_=\\='(CLP,Nf) :-
	deref(CLP,Nf,Lind),	% dereferences and turns Nf into solvable form Lind
	Lind = [Inhom,_|Hom],
	(   Hom = []
	->  compare_d(CLP, \=, 0, Inhom)
	;   % make new variable Nz = Lind
	    var_with_def_intern(t_none,CLP,Nz,Lind,0),
	    % make Nz nonzero
	    get_attr(Nz,clpcd_itf,Att),
	    setarg(8,Att,nonzero)
	).

% 'solve_<'(CLP, Nf)
%
% Solves linear inequality Nf < 0 where Nf is in normal form.

'solve_<'(CLP, Nf) :-
	split(Nf,H,I),
	ineq(H, CLP, I, Nf, strict).

% 'solve_=<'(CLP, Nf)
%
% Solves linear inequality Nf =< 0 where Nf is in normal form.

'solve_=<'(CLP, Nf) :-
	split(Nf,H,I),
	ineq(H, CLP, I, Nf, nonstrict).

maximize(CLP, Term) :-
	minimize(CLP, -Term).

%
% This is NOT coded as minimize(Expr) :- inf(Expr,Expr).
%
% because the new version of inf/2 only visits
% the vertex where the infimum is assumed and returns
% to the 'current' vertex via backtracking.
% The rationale behind this construction is to eliminate
% all garbage in the solver data structures produced by
% the pivots on the way to the extremal point caused by
% {inf,sup}/{2,4}.
%
% If we are after the infimum/supremum for minimizing/maximizing,
% this strategy may have adverse effects on performance because
% the simplex algorithm is forced to re-discover the
% extremal vertex through the equation {Inf =:= Expr}.
%
% Thus the extra code for {minimize,maximize}/1.
%
% In case someone comes up with an example where
%
%   inf(Expr,Expr)
%
% outperforms the provided formulation for minimize - so be it.
% Both forms are available to the user.
%
minimize(CLP,Term) :-
	wait_linear(CLP, Term, Nf, minimize_lin(CLP,Nf)).

% minimize_lin(CLP,Lin)
%
% Minimizes the linear expression Lin. It does so by making a new
% variable Dep and minimizes its value.

minimize_lin(CLP,Lin) :-
	deref(CLP,Lin,Lind),
	var_with_def_intern(t_none,CLP,Dep,Lind,0),
	determine_active_dec(Lind),
	iterate_dec(CLP, Dep, Inf),
	add_constraint(Dep =:= Inf, CLP).

sup(CLP,Expression,Sup) :-
	sup(CLP,Expression,Sup,[],[]).

sup(CLP,Expression,Sup,Vector,Vertex) :-
	inf(CLP,-Expression,-Sup,Vector,Vertex).

inf(CLP,Expression,Inf) :-
	inf(CLP,Expression,Inf,[],[]).

inf(CLP,Expression,Inf,Vector,Vertex) :-
	% wait until Expression becomes linear, Nf contains linear Expression
	% in normal form
	wait_linear(CLP, Expression, Nf, inf_lin(CLP,Nf,Inf,Vector,Vertex)).

inf_lin(CLP, Lin,_,Vector,_) :-
	deref(CLP,Lin,Lind),
	var_with_def_intern(t_none,CLP,Dep,Lind,0),	% make new variable Dep = Lind
	determine_active_dec(Lind),	% minimizes Lind
	iterate_dec(CLP, Dep, Inf),
	vertex_value(Vector, CLP, Values),
	nb_setval(inf,[Inf|Values]),
	fail.
inf_lin(CLP, _,Infimum,_,Vertex) :-
	nb_current(inf,L),
	nb_delete(inf),
	assign([Infimum|Vertex],CLP,L).

% assign(L1,CLP,L2)
%
% The elements of L1 are pairwise assigned to the elements of L2
% by means of asserting {X =:= Y} where X is an element of L1 and Y
% is the corresponding element of L2.

assign([],_,[]).
assign([X|Xs],CLP,[Y|Ys]) :-
	add_constraint(X =:= Y, CLP), % more defensive/expressive than X=Y
	assign(Xs,CLP,Ys).

% --------------------------------- optimization ------------------------------
%
% The _sn(S) =< 0 row might be temporarily infeasible.
% We use reconsider/2 to fix this.
%
%   s(S) e [_,0] = d +xi ... -xj, Rhs > 0 so we want to decrease s(S)
%
%   positive xi would have to be moved towards their lower bound,
%   negative xj would have to be moved towards their upper bound,
%
%   the row s(S) does not limit the lower bound of xi
%   the row s(S) does not limit the upper bound of xj
%
%   a) if some other row R is limiting xk, we pivot(R,xk),
%      s(S) will decrease and get more feasible until (b)
%   b) if there is no limiting row for some xi: we pivot(s(S),xi)
%					    xj: we pivot(s(S),xj)
%      which cures the infeasibility in one step
%


% iterate_dec(OptVar,Opt)
%
% Decreases the bound on the variables of the linear equation of OptVar as much
% as possible and returns the resulting optimal bound in Opt. Fails if for some
% variable, a status of unlimited is found.

iterate_dec(CLP, OptVar, Opt) :-
	get_attr(OptVar,clpcd_itf,Att),
	arg(4,Att,lin([I,R|H])),
	dec_step(H, CLP, Status),
	(   Status = applied
	->  iterate_dec(CLP, OptVar, Opt)
	;   Status = optimum,
	    Opt is R + I
	).

%
% Status = {optimum,unlimited(Indep,DepT),applied}
% If Status = optimum, the tables have not been changed at all.
% Searches left to right, does not try to find the 'best' pivot
% Therefore we might discover unboundedness only after a few pivots
%


dec_step_cont([],_,optimum,Cont,Cont).
dec_step_cont([l(V*K,OrdV)|Vs],CLP,Status,ContIn,ContOut) :-
	get_attr(V,clpcd_itf,Att),
	arg(2,Att,type(W)),
	arg(6,Att,class(Class)),
	(   dec_step_2_cont(W,CLP,l(V*K,OrdV),Class,Status,ContIn,ContOut)
	->  true
	;   dec_step_cont(Vs,CLP,Status,ContIn,ContOut)
	).

inc_step_cont([], _, optimum, Cont, Cont).
inc_step_cont([l(V*K,OrdV)|Vs], CLP, Status, ContIn, ContOut) :-
	get_attr(V,clpcd_itf,Att),
	arg(2,Att,type(W)),
	arg(6,Att,class(Class)),
	(   inc_step_2_cont(W, CLP, l(V*K,OrdV), Class, Status, ContIn, ContOut)
	->  true
	;   inc_step_cont(Vs, CLP, Status, ContIn, ContOut)
	).

dec_step_2_cont(t_U(U),CLP,l(V*K,OrdV),Class,Status,ContIn,ContOut) :-
	K > 0,
	(   lb(Class,CLP,OrdV,Vub-Vb-_)
	->  % found a lower bound
	    Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_u(U)),
	    replace_in_cont(ContIn,Vub,V,ContOut)
	;   Status = unlimited(V,t_u(U)),
	    ContIn = ContOut
	).
dec_step_2_cont(t_lU(L,U),CLP,l(V*K,OrdV),Class,applied,ContIn,ContOut) :-
	K > 0,
	Init is L - U,
	class_basis(Class,Deps),
	lb(Deps,CLP,OrdV,V-t_Lu(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)),
	replace_in_cont(ContIn,Vub,V,ContOut).
dec_step_2_cont(t_L(L),CLP,l(V*K,OrdV),Class,Status,ContIn,ContOut) :-
	K < 0,
	(   ub(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_l(L)),
	    replace_in_cont(ContIn,Vub,V,ContOut)
	;   Status = unlimited(V,t_l(L)),
	    ContIn = ContOut
	).
dec_step_2_cont(t_Lu(L,U),CLP,l(V*K,OrdV),Class,applied,ContIn,ContOut) :-
	K < 0,
	Init is U - L,
	class_basis(Class,Deps),
	ub(Deps,CLP,OrdV,V-t_lU(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)),
	replace_in_cont(ContIn,Vub,V,ContOut).
dec_step_2_cont(t_none,_,l(V*_,_),_,unlimited(V,t_none),Cont,Cont).



inc_step_2_cont(t_U(U),CLP,l(V*K,OrdV),Class,Status,ContIn,ContOut) :-
	K < 0,
	(   lb(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_u(U)),
	    replace_in_cont(ContIn,Vub,V,ContOut)
	;   Status = unlimited(V,t_u(U)),
	    ContIn = ContOut
	).
inc_step_2_cont(t_lU(L,U),CLP,l(V*K,OrdV),Class,applied,ContIn,ContOut) :-
	K < 0,
	Init is L - U,
	class_basis(Class,Deps),
	lb(Deps,CLP,OrdV,V-t_Lu(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)),
	replace_in_cont(ContIn,Vub,V,ContOut).
inc_step_2_cont(t_L(L),CLP,l(V*K,OrdV),Class,Status,ContIn,ContOut) :-
	K > 0,
	(   ub(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_l(L)),
	    replace_in_cont(ContIn,Vub,V,ContOut)
	;   Status = unlimited(V,t_l(L)),
	    ContIn = ContOut
	).
inc_step_2_cont(t_Lu(L,U),CLP,l(V*K,OrdV),Class,applied,ContIn,ContOut) :-
	K > 0,
	Init is U - L,
	class_basis(Class,Deps),
	ub(Deps,CLP,OrdV,V-t_lU(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)),
	replace_in_cont(ContIn,Vub,V,ContOut).
inc_step_2_cont(t_none,_,l(V*_,_),_,unlimited(V,t_none),Cont,Cont).

replace_in_cont([],_,_,[]).
replace_in_cont([H1|T1],X,Y,[H2|T2]) :-
	(   H1 == X
	->  H2 = Y,
	    T1 = T2
	;   H2 = H1,
	    replace_in_cont(T1,X,Y,T2)
	).

dec_step([], _, optimum).
dec_step([l(V*K,OrdV)|Vs], CLP, Status) :-
	get_attr(V,clpcd_itf,Att),
	arg(2,Att,type(W)),
	arg(6,Att,class(Class)),
	(   dec_step_2(W, CLP, l(V*K,OrdV), Class, Status)
	->  true
	;   dec_step(Vs, CLP, Status)
	).

dec_step_2(t_U(U),CLP,l(V*K,OrdV),Class,Status) :-
	K > 0,
	(   lb(Class,CLP,OrdV,Vub-Vb-_)
	->  % found a lower bound
	    Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_u(U))
	;   Status = unlimited(V,t_u(U))
	).
dec_step_2(t_lU(L,U),CLP,l(V*K,OrdV),Class,applied) :-
	K > 0,
	Init is L - U,
	class_basis(Class,Deps),
	lb(Deps,CLP,OrdV,V-t_Lu(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)).
dec_step_2(t_L(L),CLP,l(V*K,OrdV),Class,Status) :-
	K < 0,
	(   ub(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_l(L))
	;   Status = unlimited(V,t_l(L))
	).
dec_step_2(t_Lu(L,U),CLP,l(V*K,OrdV),Class,applied) :-
	K < 0,
	Init is U - L,
	class_basis(Class,Deps),
	ub(Deps,CLP,OrdV,V-t_lU(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)).
dec_step_2(t_none,_,l(V*_,_),_,unlimited(V,t_none)).

inc_step([], _, optimum).	% if status has not been set yet: no changes
inc_step([l(V*K,OrdV)|Vs], CLP, Status) :-
	get_attr(V,clpcd_itf,Att),
	arg(2,Att,type(W)),
	arg(6,Att,class(Class)),
	(   inc_step_2(W, CLP, l(V*K,OrdV), Class, Status)
	->  true
	;   inc_step(Vs, CLP, Status)
	).

inc_step_2(t_U(U),CLP,l(V*K,OrdV),Class,Status) :-
	K < 0,
	(   lb(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_u(U))
	;   Status = unlimited(V,t_u(U))
	).
inc_step_2(t_lU(L,U),CLP,l(V*K,OrdV),Class,applied) :-
	K < 0,
	Init is L - U,
	class_basis(Class,Deps),
	lb(Deps,CLP,OrdV,V-t_Lu(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)).
inc_step_2(t_L(L),CLP,l(V*K,OrdV),Class,Status) :-
	K > 0,
	(   ub(Class,CLP,OrdV,Vub-Vb-_)
	->  Status = applied,
	    pivot_a(CLP,Vub,V,Vb,t_l(L))
	;   Status = unlimited(V,t_l(L))
	).
inc_step_2(t_Lu(L,U),CLP,l(V*K,OrdV),Class,applied) :-
	K > 0,
	Init is U - L,
	class_basis(Class,Deps),
	ub(Deps,CLP,OrdV,V-t_lU(L,U)-Init,Vub-Vb-_),
	pivot_b(CLP,Vub,V,Vb,t_lu(L,U)).
inc_step_2(t_none,_,l(V*_,_),_,unlimited(V,t_none)).

% ------------------------- find the most constraining row --------------------
%
% The code for the lower and the upper bound are dual versions of each other.
% The only difference is in the orientation of the comparisons.
% Indeps are ruled out by their types.
% If there is no bound, this fails.
%
% *** The actual lb and ub on an indep variable X are [lu]b + b(X), where b(X)
% is the value of the active bound.
%
% Nota bene: We must NOT consider infeasible rows as candidates to
%	     leave the basis!
%
% ub(Class,CLP,OrdX,Ub)
%
% See lb/4: this is similar

ub(Class,CLP,OrdX,Ub) :-
	class_basis(Class,Deps),
	ub_first(Deps,CLP,OrdX,Ub).

% ub_first(Deps,X,Dep-W-Ub)
%
% Finds the tightest upperbound for variable X from the linear equations of
% basis variables Deps, and puts the resulting bound in Ub. Dep is the basis
% variable that generates the bound, and W is bound of that variable that has
% to be activated to achieve this.

ub_first([Dep|Deps],CLP,OrdX,Tightest) :-
	(   get_attr(Dep,clpcd_itf,Att),
	    arg(2,Att,type(Type)),
	    arg(4,Att,lin(Lin)),
	    ub_inner(Type,CLP,OrdX,Lin,W,Ub),
	    Ub >= 0
	->  ub(Deps,CLP,OrdX,Dep-W-Ub,Tightest)
	;   ub_first(Deps,CLP,OrdX,Tightest)
	).

% ub(Deps,OrdX,TightestIn,TightestOut)
%
% See lb/5: this is similar

ub([],_,_,T0,T0).
ub([Dep|Deps],CLP,OrdX,T0,T1) :-
	(   get_attr(Dep,clpcd_itf,Att),
	    arg(2,Att,type(Type)),
	    arg(4,Att,lin(Lin)),
	    ub_inner(Type,CLP,OrdX,Lin,W,Ub),
	    T0 = _-Ubb,
            compare_d(CLP, <, Ub, Ubb),
	    Ub >= 0
	->  ub(Deps,CLP,OrdX,Dep-W-Ub,T1)	% tighter bound, use new bound
	;   ub(Deps,CLP,OrdX,T0,T1)	% no tighter bound, keep current one
	).

% ub_inner(Type,CLP,OrdX,Lin,W,Ub)
%
% See lb_inner/6: this is similar

ub_inner(t_l(L),CLP,OrdX,Lin,t_L(L),Ub) :-
	nf_rhs_x(Lin,OrdX,Rhs,K),
	% Rhs is right hand side of lin. eq. Lin containing term X*K
	K < 0,
        div_d(CLP, L - Rhs, K, Ub).
ub_inner(t_u(U),CLP,OrdX,Lin,t_U(U),Ub) :-
	nf_rhs_x(Lin,OrdX,Rhs,K),
	K > 0,
        div_d(CLP, U - Rhs, K, Ub).
ub_inner(t_lu(L,U),CLP,OrdX,Lin,W,Ub) :-
	nf_rhs_x(Lin,OrdX,Rhs,K),
	(   K < 0 % use lowerbound
	->  W = t_Lu(L,U),
	    div_d(CLP, L - Rhs, K, Ub)
	;   K > 0 % use upperbound
	->  W = t_lU(L,U),
	    div_d(CLP, U - Rhs, K, Ub)
	).

% lb(Class,OrdX,Lb)
%
% Returns in Lb how much we can lower the upperbound of X without violating
% a bound of the basisvariables.
% Lb has the form Dep-W-Lb with Dep the variable whose bound is violated when
% lowering the bound for X more, W the actual bound that has to be activated
% and Lb the amount that the upperbound can be lowered.
% X has ordering OrdX and class Class.

lb(Class,CLP,OrdX,Lb) :-
	class_basis(Class,Deps),
	lb_first(Deps,CLP,OrdX,Lb).

% lb_first(Deps,CLP,OrdX,Tightest)
%
% Returns in Tightest how much we can lower the upperbound of X without
% violating a bound of Deps.
% Tightest has the form Dep-W-Lb with Dep the variable whose bound is violated
% when lowering the bound for X more, W the actual bound that has to be
% activated and Lb the amount that the upperbound can be lowered. X has
% ordering attribute OrdX.

lb_first([Dep|Deps],CLP,OrdX,Tightest) :-
	(   get_attr(Dep,clpcd_itf,Att),
	    arg(2,Att,type(Type)),
	    arg(4,Att,lin(Lin)),
	    lb_inner(Type, CLP, OrdX, Lin, W, Lb),
	    Lb =< 0 % Lb > 0 means a violated bound
	->  lb(Deps,CLP,OrdX,Dep-W-Lb,Tightest)
	;   lb_first(Deps, CLP, OrdX, Tightest)
	).

% lb(Deps,CLP,OrdX,TightestIn,TightestOut)
%
% See lb_first/3: this one does the same thing, but is used for the steps after
% the first one and remembers the tightest bound so far.

lb([],_,_,T0,T0).
lb([Dep|Deps],CLP,OrdX,T0,T1) :-
	(   get_attr(Dep,clpcd_itf,Att),
	    arg(2,Att,type(Type)),
	    arg(4,Att,lin(Lin)),
	    lb_inner(Type, CLP, OrdX, Lin, W, Lb),
	    T0 = _-Lbb,
	    compare_d(CLP, >, Lb, Lbb), % Lb > Lbb: choose the least lowering, others
					% might violate bounds
	    Lb =< 0     		% violation of a bound (without lowering)
	->  lb(Deps,OrdX,Dep-W-Lb,T1)
	;   lb(Deps,OrdX,T0,T1)
	).

% lb_inner(Type,CLP,X,Lin,W,Lb)
%
% Returns in Lb how much lower we can make X without violating a bound
% by using the linear equation Lin of basis variable B which has type
% Type and which has to activate a bound (type W) to do so.
%
% E.g. when B has a lowerbound L, then L should always be smaller than I + R.
% So a lowerbound of X (which has scalar K in Lin), could be at most
% (L-(I+R))/K lower than its upperbound (if K is positive).
% Also note that Lb should always be smaller than 0, otherwise the row is
% not feasible.
% X has ordering attribute OrdX.

lb_inner(t_l(L),CLP,OrdX,Lin,t_L(L),Lb) :-
	nf_rhs_x(Lin,OrdX,Rhs,K), % if linear equation Lin contains the term
				  % X*K, Rhs is the right hand side of that
				  % equation
	K > 0,
	div_d(CLP, L - Rhs, K, Lb).
lb_inner(t_u(U),CLP,OrdX,Lin,t_U(U),Lb) :-
	nf_rhs_x(Lin,OrdX,Rhs,K),
	K < 0, % K < 0
	div_d(CLP, U - Rhs, K, Lb).
lb_inner(t_lu(L,U),CLP,OrdX,Lin,W,Lb) :-
	nf_rhs_x(Lin,OrdX,Rhs,K),
	(   K < 0
	->  W = t_lU(L,U),
            div_d(CLP, U - Rhs, K, Lb)
	;   K > 0
	->  W = t_Lu(L,U),
	    div_d(CLP, L - Rhs, K, Lb)
	).

% ---------------------------------- equations --------------------------------
%
% backsubstitution will not make the system infeasible, if the bounds on the
% indep vars are obeyed, but some implied values might pop up in rows where X
% occurs
%	-) special case X=Y during bs -> get rid of dependend var(s), alias
%

solve(CLP,Lin) :-
	Lin = [I,_|H],
	solve(H,CLP,Lin,I,Bindings,[]),
	export_binding(Bindings).

% solve(Hom,Lin,I,Bind,BindT)
%
% Solves a linear equation Lin = [I,_|H] = 0 and exports the generated bindings

solve([],_,_,I,Bind0,Bind0) :-
	!,
	I =:= 0. % redundant or trivially unsat
solve(H,CLP,Lin,_,Bind0,BindT) :-
	sd(H,[],ClassesUniq,9-9-0,Category-Selected-_,NV,NVT),
	get_attr(Selected,clpcd_itf,Att),
	arg(5,Att,order(Ord)),
	isolate(CLP, Ord, Lin, Lin1),	% Lin = 0 => Selected = Lin1
	(   Category = 1 % classless variable, no bounds
	->  setarg(4,Att,lin(Lin1)),
	    Lin1 = [Inhom,_|Hom],
	    bs_collect_binding(Hom,Selected,Inhom,Bind0,BindT),
	    eq_classes(CLP, NV, NVT, ClassesUniq)
	;   Category = 2 % class variable, no bounds
	->  arg(6,Att,class(NewC)),
	    class_allvars(NewC,Deps),
	    (   ClassesUniq = [_] % rank increasing
	    ->	bs_collect_bindings(Deps, CLP, Ord, Lin1, Bind0, BindT)
	    ;   Bind0 = BindT,
		bs(Deps, CLP, Ord, Lin1)
	    ),
	    eq_classes(CLP, NV, NVT, ClassesUniq)
	;   Category = 3 % classless variable, all variables in Lin and
			 % Selected are bounded
	->  arg(2,Att,type(Type)),
	    setarg(4,Att,lin(Lin1)),
	    deactivate_bound(Type,Selected),
	    eq_classes(CLP, NV, NVT, ClassesUniq),
	    basis_add(Selected,Basis),
	    undet_active(Lin1),	% we can't tell which bound will likely be a
				% problem at this point
	    Lin1 = [Inhom,_|Hom],
	    bs_collect_binding(Hom,Selected,Inhom,Bind0,Bind1),	% only if
								% Hom = []
	    rcbl(Basis,CLP,Bind1,BindT) % reconsider entire basis
	;   Category = 4 % class variable, all variables in Lin and Selected
			 % are bounded
	->  arg(2,Att,type(Type)),
	    arg(6,Att,class(NewC)),
	    class_allvars(NewC,Deps),
	    (   ClassesUniq = [_] % rank increasing
	    ->	bs_collect_bindings(Deps, CLP, Ord, Lin1, Bind0, Bind1)
	    ;   Bind0 = Bind1,
		bs(Deps, CLP, Ord, Lin1)
	    ),
	    deactivate_bound(Type,Selected),
	    basis_add(Selected,Basis),
	    % eq_classes( NV, NVT, ClassesUniq),
	    %  4 -> var(NV)
	    equate(ClassesUniq,_),
	    undet_active(Lin1),
	    rcbl(Basis,CLP,Bind1,BindT)
	).

% solve_ord_x(CLP,Lin,OrdX,ClassX)
%
% Much like solve, but we solve for a particular variable of type t_none, it has
% the ordering of X and its class as input. This also means that X has a class
% which is not sure in solve_x/2.

solve_ord_x(CLP,Lin,OrdX,ClassX) :-
	Lin = [I,_|H],
	solve_ord_x(H,CLP,Lin,I,OrdX,ClassX,Bindings,[]),
	export_binding(Bindings).

solve_ord_x([],_,_,I,_,_,Bind0,Bind0) :-
	I =:= 0.
solve_ord_x([_|_],CLP,Lin,_,OrdX,ClassX,Bind0,BindT) :-
	isolate(CLP, OrdX, Lin, Lin1),
	Lin1 = [_,_|H1],
	sd(H1,[],ClassesUniq1,9-9-0,_,NV,NVT), % do sd on Lin without X, then
					       % add class of X
	ord_add_element(ClassesUniq1,ClassX,ClassesUniq),
	class_allvars(ClassX,Deps),
	(   ClassesUniq = [_] % rank increasing
	->  bs_collect_bindings(Deps, CLP, OrdX, Lin1, Bind0, BindT)
	;   Bind0 = BindT,
	    bs(Deps, CLP, OrdX, Lin1)
	),
	eq_classes(CLP,NV,NVT,ClassesUniq).

% sd(H,[],ClassesUniq,9-9-0,Category-Selected-_,NV,NVT)

% sd(Hom,ClassesIn,ClassesOut,PreferenceIn,PreferenceOut,[NV|NVTail],NVTail)
%
% ClassesOut is a sorted list of the different classes that are either in
% ClassesIn or that are the classes of the variables in Hom. Variables that do
% not belong to a class yet, are put in the difference list NV.

sd([],Class0,Class0,Preference0,Preference0,NV0,NV0).
sd([l(X*K,_)|Xs],Class0,ClassN,Preference0,PreferenceN,NV0,NVt) :-
	get_attr(X,clpcd_itf,Att),
	(   arg(6,Att,class(Xc)) % old: has class
	->  NV0 = NV1,
	    ord_add_element(Class0,Xc,Class1),
	    (   arg(2,Att,type(t_none))
	    ->  preference(Preference0,2-X-K,Preference1)
		    % has class, no bounds => category 2
	    ;   preference(Preference0,4-X-K,Preference1)
		    % has class, is bounded => category 4
	    )
	;   % new: has no class
	    Class1 = Class0,
	    NV0 = [X|NV1], % X has no class yet, add to list of new variables
	    (   arg(2,Att,type(t_none))
	    ->  preference(Preference0,1-X-K,Preference1)
		    % no class, no bounds => category 1
	    ;   preference(Preference0,3-X-K,Preference1)
		    % no class, is bounded => category 3
	    )
	),
	sd(Xs,Class1,ClassN,Preference1,PreferenceN,NV1,NVt).

%
% A is best sofar, B is current
% smallest prefered
preference(A,B,Pref) :-
	A = Px-_-_,
	B = Py-_-_,
	(   Px < Py
	->  Pref = A
	;   Pref = B
	).

% eq_classes(CLP,NV,NVTail,Cs)
%
% Attaches all classless variables NV to a new class and equates all other
% classes with this class. The equate operation only happens after attach_class
% because the unification of classes can bind the tail of the AllVars attribute
% to a nonvar and then the attach_class operation wouldn't work.

eq_classes(_,NV,_,Cs) :-
	var(NV),
	!,
	equate(Cs,_).
eq_classes(CLP,NV,NVT,Cs) :-
	class_new(Su,CLP,NV,NVT,[]), % make a new class Su with NV as the variables
	attach_class(NV,Su), % attach the variables NV to Su
	equate(Cs,Su).

equate([],_).
equate([X|Xs],X) :- equate(Xs,X).

%
% assert: none of the Vars has a class attribute yet
%
attach_class(Xs,_) :-
	var(Xs), % Tail
	!.
attach_class([X|Xs],Class) :-
	get_attr(X,clpcd_itf,Att),
	setarg(6,Att,class(Class)),
	attach_class(Xs,Class).

% unconstrained(Lin,Uc,Kuc,Rest)
%
% Finds an unconstrained variable Uc (type(t_none)) in Lin with scalar Kuc and
% removes it from Lin to return Rest.

unconstrained(Lin,Uc,Kuc,Rest) :-
	Lin = [_,_|H],
	sd(H,[],_,9-9-0,Category-Uc-_,_,_),
	Category =< 2,
	get_attr(Uc,clpcd_itf,Att),
	arg(5,Att,order(OrdUc)),
	delete_factor(OrdUc,Lin,Rest,Kuc).

%
% point the vars in Lin into the same equivalence class
% maybe join some global data
%
same_class([],_).
same_class([l(X*_,_)|Xs],Class) :-
	get_or_add_class(X,Class),
	same_class(Xs,Class).

% allvars(X,Allvars)
%
% Allvars is a list of all variables in the class to which X belongs.

allvars(X,Allvars) :-
	get_attr(X,clpcd_itf,Att),
	arg(6,Att,class(C)),
	class_allvars(C,Allvars).

% deactivate_bound(Type,Variable)
%
% The Type of the variable is changed to reflect the deactivation of its
% bounds.
% t_L(_) becomes t_l(_), t_lU(_,_) becomes t_lu(_,_) and so on.

deactivate_bound(t_l(_),_).
deactivate_bound(t_u(_),_).
deactivate_bound(t_lu(_,_),_).
deactivate_bound(t_L(L),X) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_l(L))).
deactivate_bound(t_Lu(L,U),X) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_lu(L,U))).
deactivate_bound(t_U(U),X) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_u(U))).
deactivate_bound(t_lU(L,U),X) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_lu(L,U))).

% intro_at(X,Value,Type)
%
% Variable X gets new type Type which reflects the activation of a bound with
% value Value. In the linear equations of all the variables belonging to the
% same class as X, X is substituted by [0,Value,X] to reflect the new active
% bound.

intro_at(X,Value,Type) :-
	get_attr(X,clpcd_itf,Att),
	arg(5,Att,order(Ord)),
	arg(6,Att,class(Class)),
	setarg(2,Att,type(Type)),
	(   Value =:= 0
	->  true
	;   backsubst_delta(_, Class, Ord, X, Value)
	).

% undet_active(Lin)
%
% For each variable in the homogene part of Lin, a bound is activated
% if an inactive bound exists. (t_l(L) becomes t_L(L) and so on)

undet_active([_,_|H]) :-
	undet_active_h(H).

% undet_active_h(Hom)
%
% For each variable in homogene part Hom, a bound is activated if an
% inactive bound exists (t_l(L) becomes t_L(L) and so on)

undet_active_h([]).
undet_active_h([l(X*_,_)|Xs]) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	undet_active(Type,X),
	undet_active_h(Xs).

% undet_active(Type,Var)
%
% An inactive bound of Var is activated if such exists
% t_lu(L,U) is arbitrarily chosen to become t_Lu(L,U)

undet_active(t_none,_).	% type_activity
undet_active(t_L(_),_).
undet_active(t_Lu(_,_),_).
undet_active(t_U(_),_).
undet_active(t_lU(_,_),_).
undet_active(t_l(L),X) :- intro_at(X,L,t_L(L)).
undet_active(t_u(U),X) :- intro_at(X,U,t_U(U)).
undet_active(t_lu(L,U),X) :- intro_at(X,L,t_Lu(L,U)).

% determine_active_dec(Lin)
%
% Activates inactive bounds on the variables of Lin if such bounds exist.
% If the type of a variable is t_none, this fails. This version is aimed
% to make the R component of Lin as small as possible in order not to violate
% an upperbound (see reconsider/2)

determine_active_dec([_,_|H]) :-
	determine_active(H,-1).

% determine_active_inc(Lin)
%
% Activates inactive bounds on the variables of Lin if such bounds exist.
% If the type of a variable is t_none, this fails. This version is aimed
% to make the R component of Lin as large as possible in order not to violate
% a lowerbound (see reconsider/2)

determine_active_inc([_,_|H]) :-
	determine_active(H,1).

% determine_active(Hom,S)
%
% For each variable in Hom, activates its bound if it is not yet activated.
% For the case of t_lu(_,_) the lower or upper bound is activated depending on
% K and S:
% If sign of K*S is negative, then lowerbound, otherwise upperbound.

determine_active([],_).
determine_active([l(X*K,_)|Xs],S) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	determine_active(Type,X,K,S),
	determine_active(Xs,S).

determine_active(t_L(_),_,_,_).
determine_active(t_Lu(_,_),_,_,_).
determine_active(t_U(_),_,_,_).
determine_active(t_lU(_,_),_,_,_).
determine_active(t_l(L),X,_,_) :- intro_at(X,L,t_L(L)).
determine_active(t_u(U),X,_,_) :- intro_at(X,U,t_U(U)).
determine_active(t_lu(L,U),X,K,S) :-
	KS is K*S,
	(   KS < 0
	->  intro_at(X,L,t_Lu(L,U))
	;   KS > 0
	->  intro_at(X,U,t_lU(L,U))
	).

%
% Careful when an indep turns into t_none !!!
%

detach_bounds(CLP, V) :-
	get_attr(V,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(4,Att,lin(Lin)),
	arg(5,Att,order(OrdV)),
	arg(6,Att,class(Class)),
	setarg(2,Att,type(t_none)),
	setarg(3,Att,strictness(0)),
	(   indep(CLP, Lin, OrdV)
	->  (   ub(Class,CLP,OrdV,Vub-Vb-_)
	    ->	% exchange against thightest
		class_basis_drop(Class,Vub),
		pivot(CLP, Vub, Class, OrdV, Vb, Type)
	    ;   lb(Class,CLP,OrdV,Vlb-Vb-_)
	    ->  class_basis_drop(Class,Vlb),
		pivot(CLP, Vlb, Class, OrdV, Vb, Type)
	    ;   true
	    )
	;   class_basis_drop(Class,V)
	).

detach_bounds_vlv(CLP,OrdV,Lin,Class,Var,NewLin) :-
	(   indep(CLP, Lin, OrdV)
	->  Lin = [_,R|_],
	    (   ub(Class,CLP,OrdV,Vub-Vb-_)
	    ->  % in verify_lin, class might contain two occurrences of Var,
		% but it doesn't matter which one we delete
		class_basis_drop(Class,Var),
		pivot_vlv(CLP, Vub, Class, OrdV, Vb, R, NewLin)
	    ;   lb(Class,CLP,OrdV,Vlb-Vb-_)
	    ->  class_basis_drop(Class,Var),
		pivot_vlv(CLP, Vlb, Class, OrdV, Vb, R, NewLin)
	    ;   NewLin = Lin
	    )
	;   NewLin = Lin,
	    class_basis_drop(Class,Var)
	).

% ----------------------------- manipulate the basis --------------------------

% basis_add(X,NewBasis)
%
% NewBasis is the result of adding X to the basis of the class to which X
% belongs.

basis_add(X,NewBasis) :-
	get_attr(X,clpcd_itf,Att),
	arg(6,Att,class(Cv)),
	class_basis_add(Cv,X,NewBasis).

% basis_pivot(Leave,Enter)
%
% Removes Leave from the basis of the class to which it belongs, and adds
% Enter to that basis.

basis_pivot(Leave,Enter) :-
	get_attr(Leave,clpcd_itf,Att),
	arg(6,Att,class(Cv)),
	class_basis_pivot(Cv,Enter,Leave).

% ----------------------------------- pivot -----------------------------------

% pivot_a(Dep,Indep,IndepT,DepT)
%
% Removes Dep from the basis, puts Indep in, and pivots the equation of
% Dep to become one of Indep. The type of Dep becomes DepT (which means
% it gets deactivated), the type of Indep becomes IndepT (which means it
% gets activated)


pivot_a(CLP,Dep,Indep,Vb,Wd) :-
	basis_pivot(Dep,Indep),
	get_attr(Indep,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(5,Att,order(Ord)),
	arg(6,Att,class(Class)),
	pivot(CLP,Dep,Class,Ord,Vb,Type),
	get_attr(Indep,clpcd_itf,Att2), %changed?
	setarg(2,Att2,type(Wd)).

pivot_b(CLP,Vub,V,Vb,Wd) :-
	(   Vub == V
	->  get_attr(V,clpcd_itf,Att),
	    arg(5,Att,order(Ord)),
	    arg(6,Att,class(Class)),
	    setarg(2,Att,type(Vb)),
	    pivot_b_delta(Vb,Delta), % nonzero(Delta)
	    backsubst_delta(CLP, Class, Ord, V, Delta)
	;   pivot_a(CLP,Vub,V,Vb,Wd)
	).

pivot_b_delta(t_Lu(L,U),Delta) :- Delta is L-U.
pivot_b_delta(t_lU(L,U),Delta) :- Delta is U-L.

% select_active_bound(Type,Bound)
%
% Returns the bound that is active in Type (if such exists, 0 otherwise)

select_active_bound(t_L(L),L).
select_active_bound(t_Lu(L,_),L).
select_active_bound(t_U(U),U).
select_active_bound(t_lU(_,U),U).
select_active_bound(t_none,0).
%
% for project.pl
%
select_active_bound(t_l(_),0).
select_active_bound(t_u(_),0).
select_active_bound(t_lu(_,_),0).

% pivot(Dep,Class,IndepOrd,DepAct,IndAct)
%
% See pivot/2.
% In addition, variable Indep with ordering IndepOrd has an active bound IndAct

%
%
% Pivot taking care of rhs and active states
%
pivot(CLP,Dep,Class,IndepOrd,DepAct,IndAct) :-
	get_attr(Dep,clpcd_itf,Att),
	arg(4,Att,lin(H)),
	arg(5,Att,order(DepOrd)),
	setarg(2,Att,type(DepAct)),
	select_active_bound(DepAct,AbvD), % New current value for Dep
	select_active_bound(IndAct,AbvI), % Old current value of Indep
	delete_factor(IndepOrd,H,H0,Coeff), % Dep = ... + Coeff*Indep + ...
	AbvDm is -AbvD,
	AbvIm is -AbvI,
	add_linear_f1(CLP, [0,AbvIm], Coeff, H0, H1),
	div_d(CLP, -1, Coeff, K),
	add_linear_ff(CLP, H1, K, [0,AbvDm,l(Dep* -1,DepOrd)], K, H2),
	    % Indep = -1/Coeff*... + 1/Coeff*Dep
	add_linear_11(CLP, H2, [0,AbvIm], Lin),
	backsubst(CLP, Class, IndepOrd, Lin).

% Rewrite Dep = ... + Coeff*Indep + ...
% into Indep = ... + -1/Coeff*Dep + ...
%
% For backsubstitution, old current value of Indep must be removed from RHS
% New current value of Dep must be added to RHS
% For solving: old current value of Indep should be out of RHS

pivot_vlv(CLP,Dep,Class,IndepOrd,DepAct,AbvI,Lin) :-
	get_attr(Dep,clpcd_itf,Att),
	arg(4,Att,lin(H)),
	arg(5,Att,order(DepOrd)),
	setarg(2,Att,type(DepAct)),
	select_active_bound(DepAct,AbvD), % New current value for Dep
	delete_factor(IndepOrd,H,H0,Coeff), % Dep = ... + Coeff*Indep + ...
	AbvDm is -AbvD,
	AbvIm is -AbvI,
	add_linear_f1(CLP, [0,AbvIm], Coeff, H0, H1),
	div_d(CLP, -1, Coeff, K),
	add_linear_ff(CLP, H1, K, [0,AbvDm,l(Dep* -1,DepOrd)], K, Lin),
	    % Indep = -1/Coeff*... + 1/Coeff*Dep
	add_linear_11(CLP, Lin, [0,AbvIm], SubstLin),
	backsubst(CLP, Class, IndepOrd, SubstLin).

% backsubst_delta(Class,OrdX,X,Delta)
%
% X with ordering attribute OrdX, is substituted in all linear equations of
% variables in the class Class, by linear equation [0,Delta,l(X*1,OrdX)]. This
% reflects the activation of a bound.

backsubst_delta(CLP, Class, OrdX, X, Delta) :-
	backsubst(CLP, Class, OrdX, [0,Delta,l(X*1,OrdX)]).

% backsubst(Class,OrdX,Lin)
%
% X with ordering OrdX is substituted in all linear equations of variables in
% the class Class, by linear equation Lin

backsubst(CLP, Class, OrdX, Lin) :-
	class_allvars(Class,Allvars),
	bs(Allvars, CLP, OrdX, Lin).

% bs(Vars,OrdV,Lin)
%
% In all linear equations of the variables Vars, variable V with ordering
% attribute OrdV is substituted by linear equation Lin.
%
% valid if nothing will go ground
%

bs(Xs, _, _, _) :-
	var(Xs),
	!.
bs([X|Xs], CLP, OrdV, Lin) :-
	(   get_attr(X,clpcd_itf,Att),
	    arg(4,Att,lin(LinX)),
	    nf_substitute(CLP, OrdV, Lin, LinX, LinX1) % does not change attributes
	->  setarg(4,Att,lin(LinX1)),
	    bs(Xs, CLP, OrdV, Lin)
	;   bs(Xs, CLP, OrdV, Lin)
	).

%
% rank increasing backsubstitution
%

% bs_collect_bindings(Deps,SelectedOrd,Lin,Bind,BindT)
%
% Collects bindings (of the form [X-I] where X = I is the binding) by
% substituting Selected in all linear equations of the variables Deps (which
% are of the same class), by Lin. Selected has ordering attribute SelectedOrd.
%
% E.g. when V = 2X + 3Y + 4, X = 3V + 2Z and Y = 4X + 3
% we can substitute V in the linear equation of X: X = 6X + 9Y + 2Z + 12
% we can't substitute V in the linear equation of Y of course.

bs_collect_bindings(Xs, _, _, _, Bind0, BindT) :-
	var(Xs),
	!,
	Bind0 = BindT.
bs_collect_bindings([X|Xs], CLP, OrdV, Lin, Bind0, BindT) :-
	(   get_attr(X,clpcd_itf,Att),
	    arg(4,Att,lin(LinX)),
	    nf_substitute(CLP, OrdV, Lin, LinX, LinX1) % does not change attributes
	->  setarg(4,Att,lin(LinX1)),
	    LinX1 = [Inhom,_|Hom],
	    bs_collect_binding(Hom,X,Inhom,Bind0,Bind1),
	    bs_collect_bindings(Xs, CLP, OrdV, Lin, Bind1, BindT)
	;   bs_collect_bindings(Xs, CLP, OrdV, Lin, Bind0, BindT)
	).

% bs_collect_binding(Hom,Selected,Inhom,Bind,BindT)
%
% Collects binding following from Selected = Hom + Inhom.
% If Hom = [], returns the binding Selected-Inhom (=0)
%
bs_collect_binding([],X,Inhom) --> [X-Inhom].
bs_collect_binding([_|_],_,_) --> [].

%
% reconsider the basis
%

% rcbl(Basis,Bind,BindT)
%
%

rcbl([],_,Bind0,Bind0).
rcbl([X|Continuation],CLP,Bind0,BindT) :-
	(   rcb_cont(CLP,X,Status,Violated,Continuation,NewContinuation) % have a culprit
	->  rcbl_status(Status,CLP,X,NewContinuation,Bind0,BindT,Violated)
	;   rcbl(Continuation,CLP,Bind0,BindT)
	).

rcb_cont(CLP,X,Status,Violated,ContIn,ContOut) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(4,Att,lin([I,R|H])),
	(   Type = t_l(L) % case 1: lowerbound: R + I should always be larger
			  % than the lowerbound
	->  compare_d(CLP, =<, R + I, L),
	    Violated = l(L),
	    inc_step_cont(H, CLP, Status, ContIn, ContOut)
	;   Type = t_u(U) % case 2: upperbound: R + I should always be smaller
			  % than the upperbound
	->  compare_d(CLP, >, R + I, U),
	    Violated = u(U),
	    dec_step_cont(H,CLP,Status,ContIn,ContOut)
	;   Type = t_lu(L,U) % case 3: check both
	->  At is R + I,
	    (   compare_d(CLP, =<, At, L)
	    ->	Violated = l(L),
		inc_step_cont(H, CLP, Status, ContIn, ContOut)
	    ;   compare_d(CLP, >=, At, U)
	    ->	Violated = u(U),
		dec_step_cont(H,CLP,Status,ContIn,ContOut)
	    )
	). % other types imply nonbasic variable or unbounded variable

%
% reconsider one element of the basis
% later: lift the binds
%
reconsider(CLP,X) :-
	rcb(CLP,X,Status,Violated),
	!,
	rcbl_status(Status,CLP,X,[],Binds,[],Violated),
	export_binding(Binds).
reconsider(_,_).

%
% Find a basis variable out of its bound or at its bound
% Try to move it into whithin its bound
%   a) impossible -> fail
%   b) optimum at the bound -> implied value
%   c) else look at the remaining basis variables
%
%
% Idea: consider a variable V with linear equation Lin.
% When a bound on a variable X of Lin gets activated, its value, multiplied
% with the scalar of X, is added to the R component of Lin.
% When we consider the lowerbound of V, it must be smaller than R + I, since R
% contains at best the lowerbounds of the variables in Lin (but could contain
% upperbounds, which are of course larger). So checking this can show the
% violation of a bound of V. A similar case works for the upperbound.

rcb(CLP,X,Status,Violated) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(4,Att,lin([I,R|H])),
	(   Type = t_l(L) % case 1: lowerbound: R + I should always be larger
			  % than the lowerbound
	->  compare_d(CLP, =<, R + I, L),
	    Violated = l(L),
	    inc_step(H, CLP, Status)
	;   Type = t_u(U) % case 2: upperbound: R + I should always be smaller
			  % than the upperbound
	->  compare_d(CLP, >=, R + I, U),
	    Violated = u(U),
	    dec_step(H, CLP, Status)
	;   Type = t_lu(L,U) % case 3: check both
	->  At is R + I,
	    (   compare_d(CLP, =<, At, L)
	    ->	Violated = l(L),
		inc_step(H, CLP, Status)
	    ;   compare_d(CLP, >=, At, U)
	    ->	Violated = u(U),
		dec_step(H, CLP, Status)
	    )
	). % other types imply nonbasic variable or unbounded variable

% rcbl_status(Status,CLP,X,Continuation,[Bind|BindT],BindT,Violated)
%
%

rcbl_status(optimum,CLP,X,Cont,B0,Bt,Violated) :- rcbl_opt(Violated,CLP,X,Cont,B0,Bt).
rcbl_status(applied,CLP,X,Cont,B0,Bt,Violated) :- rcbl_app(Violated,CLP,X,Cont,B0,Bt).
rcbl_status(unlimited(Indep,DepT),CLP,X,Cont,B0,Bt,Violated) :-
	rcbl_unl(Violated,CLP,X,Cont,B0,Bt,Indep,DepT).

%
% Might reach optimum immediately without changing the basis,
% but in general we must assume that there were pivots.
% If the optimum meets the bound, we backsubstitute the implied
% value, solve will call us again to check for further implied
% values or unsatisfiability in the rank increased system.
%
rcbl_opt(l(L),CLP,X,Continuation,B0,B1) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(3,Att,strictness(Strict)),
	arg(4,Att,lin(Lin)),
	Lin = [I,R|_],
	Opt is R + I,
	(   compare_d(CLP, <, L, Opt)
	->  narrow_u(Type,X,Opt), % { X =< Opt }
	    rcbl(Continuation,CLP,B0,B1)
	;   compare_d(CLP, =, L, Opt),
	    Strict /\ 2 =:= 0, % meets lower
	    Mop is -Opt,
	    normalize_scalar(Mop,MopN),
	    add_linear_11(CLP, MopN, Lin, Lin1),
	    Lin1 = [Inhom,_|Hom],
	    (   Hom = []
	    ->  rcbl(Continuation,CLP,B0,B1) % would not callback
	    ;   solve(Hom,CLP,Lin1,Inhom,B0,B1)
	    )
	).
rcbl_opt(u(U),CLP,X,Continuation,B0,B1) :-
	get_attr(X,clpcd_itf,Att),
	arg(2,Att,type(Type)),
	arg(3,Att,strictness(Strict)),
	arg(4,Att,lin(Lin)),
	Lin = [I,R|_],
	Opt is R + I,
	(   compare_d(CLP, >, U, Opt)
	->  narrow_l(Type,X,Opt), % { X >= Opt }
	    rcbl(Continuation,CLP,B0,B1)
	;   compare_d(CLP, =, U, Opt),
	    Strict /\ 1 =:= 0, % meets upper
	    Mop is -Opt,
	    normalize_scalar(Mop,MopN),
	    add_linear_11(CLP, MopN, Lin, Lin1),
	    Lin1 = [Inhom,_|Hom],
	    (   Hom = []
	    ->  rcbl(Continuation,CLP,B0,B1) % would not callback
	    ;   solve(Hom,CLP,Lin1,Inhom,B0,B1)
	    )
	).

%
% Basis has already changed when this is called
%
rcbl_app(l(L),CLP,X,Continuation,B0,B1) :-
	get_attr(X,clpcd_itf,Att),
	arg(4,Att,lin([I,R|H])),
	(   compare_d(CLP, >, R + I, L) % within bound now
	->  rcbl(Continuation,CLP,B0,B1)
	;   inc_step(H, CLP, Status),
	    rcbl_status(Status,CLP,X,Continuation,B0,B1,l(L))
	).
rcbl_app(u(U),CLP,X,Continuation,B0,B1) :-
	get_attr(X,clpcd_itf,Att),
	arg(4,Att,lin([I,R|H])),
	(   compare_d(CLP, <, R + I, U) % within bound now
	->  rcbl(Continuation,CLP,B0,B1)
	;   dec_step(H, CLP, Status),
	    rcbl_status(Status,CLP,X,Continuation,B0,B1,u(U))
	).
%
% This is never called for a t_lu culprit
%
rcbl_unl(l(L),CLP,X,Continuation,B0,B1,Indep,DepT) :-
	pivot_a(CLP,X,Indep,t_L(L),DepT), % changes the basis
	rcbl(Continuation,CLP,B0,B1).
rcbl_unl(u(U),CLP,X,Continuation,B0,B1,Indep,DepT) :-
	pivot_a(CLP,X,Indep,t_U(U),DepT), % changes the basis
	rcbl(Continuation,CLP,B0,B1).

% narrow_u(Type,X,U)
%
% Narrows down the upperbound of X (type Type) to U.
% Fails if Type is not t_u(_) or t_lu(_)

narrow_u(t_u(_),X,U) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_u(U))).
narrow_u(t_lu(L,_),X,U) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_lu(L,U))).

% narrow_l(Type,X,L)
%
% Narrows down the lowerbound of X (type Type) to L.
% Fails if Type is not t_l(_) or t_lu(_)

narrow_l( t_l(_),    X, L) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_l(L))).

narrow_l( t_lu(_,U), X, L) :-
	get_attr(X,clpcd_itf,Att),
	setarg(2,Att,type(t_lu(L,U))).
