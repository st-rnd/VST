Load loadpath.
Require Import msl.predicates_hered.
Require Import veric.sim veric.step_lemmas veric.base veric.expr veric.extspec 
               veric.juicy_extspec.
Require Import ListSet.

Set Implicit Arguments.

Lemma extfunct_eqdec : forall ef1 ef2 : AST.external_function, 
  {ef1=ef2} + {~ef1=ef2}.
Proof. intros ef1 ef2; repeat decide equality; apply Address.EqDec_int. Qed.

Definition is_true (b: bool) := b=true.
Local Coercion is_true: bool >-> Sortclass.

Notation IN := (ListSet.set_mem extfunct_eqdec).
Notation NOTIN := (fun ef l => ListSet.set_mem extfunct_eqdec ef l = false).
Notation DIFF := (ListSet.set_diff extfunct_eqdec).

Lemma in_diff (ef: AST.external_function) (l r: list AST.external_function) :
  IN ef l -> NOTIN ef r -> IN ef (DIFF l r).
Proof.
simpl; intros H1 H2; apply set_mem_correct2. 
apply set_mem_correct1 in H1.
apply set_mem_complete1 in H2.
apply set_diff_intro; auto.
Qed.

(*linking external specification "sigma" with an extension implementing
   functions in "handled" corresponds to removing the functions in handled from
   the external specification*)

Definition link_ext_spec (M Z: Type) (handled: list AST.external_function) 
  (sigma: external_specification M AST.external_function Z) :=
  Build_external_specification M AST.external_function Z
    (ext_spec_type sigma)
    (fun (ef: AST.external_function) (x: ext_spec_type sigma ef)
         (tys: list typ) (args: list val) (z: Z) (m: M) => 
             if ListSet.set_mem extfunct_eqdec ef handled then False 
             else ext_spec_pre sigma ef x tys args z m)
    (fun (ef: AST.external_function) (x: ext_spec_type sigma ef)
         (ty: option typ) (ret: option val) (z: Z) (m: M) => 
             if ListSet.set_mem extfunct_eqdec ef handled then True
             else ext_spec_post sigma ef x ty ret z m).

Program Definition link_juicy_ext_spec (Z: Type) (handled: list AST.external_function)
  (sigma: juicy_ext_spec Z) :=
  Build_juicy_ext_spec Z (link_ext_spec handled sigma) _ _.
Next Obligation.
if_tac; [unfold hereditary; auto|].
generalize JE_pre_hered; unfold hereditary; intros; eapply H; eauto.
Qed.
Next Obligation.
if_tac; [unfold hereditary; auto|].
generalize JE_post_hered; unfold hereditary; intros; eapply H; eauto.
Qed.

(*an external signature "ext_sig" is a list of handled functions together with
   an external specification*)

Section ExtSig.
Variables M Z: Type.

Inductive ext_sig := 
  mkextsig: forall (functs: list AST.external_function)
                   (extspec: external_specification M external_function Z), 
    ext_sig.

Definition extsig2functs (sigma: ext_sig) := 
  match sigma with mkextsig l _ => l end.
Coercion extsig2functs : ext_sig >-> list.

Definition extsig2extspec (sigma: ext_sig) :=
  match sigma with mkextsig functs spec => spec end.
Coercion extsig2extspec : ext_sig >-> external_specification.

Definition spec_of (ef: AST.external_function) (sigma: ext_sig) :=
  (ext_spec_pre sigma ef, ext_spec_post sigma ef).

End ExtSig.

Record juicy_ext_sig (Z: Type): Type := mkjuicyextsig {
  JE_functs:> list external_function;
  JE_extspec:> juicy_ext_spec Z
}.

Definition juicy_extsig2extsig (Z: Type) (je: juicy_ext_sig Z) :=
  mkextsig (JE_functs je) (JE_extspec je).
Coercion juicy_extsig2extsig: juicy_ext_sig >-> ext_sig.

Definition link (T Z: Type) (esig: ext_sig T Z) 
      (handled: list AST.external_function) :=
  mkextsig handled (link_ext_spec handled esig).

Definition juicy_link (Z: Type) (jesig: juicy_ext_sig Z) 
      (handled: list AST.external_function) :=
  mkjuicyextsig handled (link_juicy_ext_spec handled jesig).

(*ef:{P}{Q} (ext_sig spec) is a subtype of ef:{P'}{Q'} (spec. assumed by client)*)
Definition linkable (M Z: Type) 
      (handled: list AST.external_function) 
      (client_sig: ext_sig M Z) (ext_sig: ext_sig M Z) := 
  forall ef P Q P' Q', 
    IN ef (DIFF client_sig handled) -> 
    spec_of ef ext_sig = (P, Q) -> 
    spec_of ef client_sig = (P', Q') -> 
    forall x' tys args m z, P' x' tys args z m -> 
      exists x, P x tys args z m /\
      forall ty ret m' z', Q x ty ret z' m' -> Q' x' ty ret z' m'.

Module Extension. 
Record Sig
  (G: Type) (*global environments*)
  (xT: Type) (*corestates of extended semantics*)
  (cT: Type) (*corestates of core semantics*)
  (M: Type) (*memories*)
  (D: Type) (*initialization data*)
  (Z Zint Zext: Type) 

  (esem: CoreSemantics G xT M D) (*extended semantics*)
  (csem: nat -> option (CoreSemantics G cT M D)) (*a set of core semantics*)

  (client_sig: ext_sig M Z) 
  (esig: ext_sig M Z)
  (handled: list AST.external_function) := Make {

    (*generalized projection of core i from state s*)
    proj_core : xT -> nat -> option cT;
    core_exists : forall ge i s c' m s' m', 
      corestep esem ge s m s' m' -> proj_core s' i = Some c' -> 
      exists c, proj_core s i = Some c;

    (*the active (i.e., currently scheduled) core*)
    active : xT -> nat;
    active_csem : forall s, exists CS, csem (active s) = Some CS;
    active_proj_core : forall s, exists c, proj_core s (active s) = Some c;

    (*runnable = Some i when active s = i and i is runnable (i.e., not blocked
      waiting on an external function call)*)
    runnable : G -> xT -> option nat;
    runnable_active : forall ge s i, 
      runnable ge s = Some i -> active s = i;
    runnable_none : forall ge s c CS,
      runnable ge s = None -> 
      csem (active s) = Some CS -> proj_core s (active s) = Some c -> 
      (exists rv, safely_halted CS ge c = Some rv) \/
      (exists ef, exists args, at_external CS c = Some (ef, args));

    (*a core is no longer "at external" once the extension has returned 
      to it with the result of the call on which it was blocked*)
    after_at_external_excl : forall i CS c c' ret,
      csem i = Some CS -> after_external CS ret c = Some c' -> 
      at_external CS c' = None;

    at_external_client_sig: forall s i CS c ef args sig,
      csem i = Some CS -> proj_core s i = Some c -> 
      at_external CS c = Some (ef, sig, args) -> 
      IN ef client_sig;
    notat_external_handled: forall s i CS c ef args sig,
      csem i = Some CS -> proj_core s i = Some c -> 
      at_external CS c = Some (ef, sig, args) -> 
      at_external esem s = None -> 
      IN ef handled;
    at_external_not_handled: forall s ef args sig,
      at_external esem s = Some (ef, sig, args) -> 
      NOTIN ef handled;

    (*type xT embeds Zint*)
    proj_zint: xT -> Zint;
    proj_zext: Z -> Zext;
    zmult: Zint -> Zext -> Z;
    zmult_proj: forall zint zext, proj_zext (zmult zint zext) = zext;
    ext_upd_at_external : forall ge s m s' m',
      corestep esem ge s m s' m' -> 
      proj_zint s = proj_zint s';

    (*csem and esem are signature linkable*)
    esem_csem_linkable: linkable handled client_sig esig;

    (*a global invariant characterizing "safe" extensions*)
    all_safe (ge: G) (n: nat) (z: Z) (w: xT) (m: M) :=
      forall i CS c, csem i = Some CS -> proj_core w i = Some c -> 
        safeN CS client_sig ge n z c m
}.

End Extension. 

Implicit Arguments Extension.Make [G xT cT M D Z Zint Zext].

(*an extension E is safe when all states satisfy the "all_safe" invariant*)

Section SafeExtension.
Variables (G T C M D Z Zint Zext: Type)
  (esem: CoreSemantics G T M D) (csem: nat -> option (CoreSemantics G C M D))
  (client_sig: ext_sig M Z) (esig: ext_sig M Z) (handled: list AST.external_function).

Import Extension.

Definition safe_extension (E: Extension.Sig Zint Zext esem csem client_sig esig handled) :=
  forall ge n s m z, 
    E.(all_safe) ge n (zmult E (proj_zint E s) z) s m -> 
    safeN esem (link esig handled) ge n (zmult E (proj_zint E s) z) s m.

End SafeExtension.

Section SafetyMonotonicity.
Variables (G cT M D Zext: Type) (CS: CoreSemantics G cT M D)
  (client_sig: ext_sig M Z) (handled: ext_sig M Zext).

Lemma safety_monotonicity : forall ge n z c m,
  safeN CS (link client_sig handled) ge n z c m -> 
  safeN CS client_sig ge n z c m.
Proof. 
intros ge n; induction n; auto.
intros  ora c m; simpl; intros H1.
destruct (at_external CS c).
destruct p; destruct p.
destruct (safely_halted CS ge c).
auto.
destruct H1 as [x [H1 H2]].
if_tac in H1.
elimtype False; apply H1.
exists x; split; auto.
intros ret m' z' H3; destruct (H2 ret m' z' H3) as [c' [H4 H5]].
exists c'; split; auto.
destruct (safely_halted CS ge c); auto.
destruct H1 as [c' [m' [H1 H2]]].
exists c'; exists m'; split; auto.
Qed.

End SafetyMonotonicity.

Section SafetyCriteria.
Variables
  (G xT cT M D Z Zint Zext: Type) 
  (esem: CoreSemantics G xT M D) 
  (csem: nat -> option (CoreSemantics G cT M D))
  (client_sig: ext_sig M Z)
  (esig: ext_sig M Z)
  (handled: list AST.external_function)
  (E: Extension.Sig Zint Zext esem csem client_sig esig handled).

Definition proj_zint := E.(Extension.proj_zint). 
Local Coercion proj_zint : xT >-> Zint.

Definition proj_zext := E.(Extension.proj_zext).
Local Coercion proj_zext : Z >-> Zext.

Notation ALL_SAFE := E.(Extension.all_safe).
Notation PROJ_CORE := E.(Extension.proj_core).
Notation "zint \o zext" := (E.(Extension.zmult) zint zext) (at level 66, left associativity). 
Notation ACTIVE := (E.(Extension.active)).
Notation RUNNABLE := (E.(Extension.runnable)).
Notation "'CORE' i 'is' ( CS , c ) 'in' s" := 
  (csem i = Some CS /\ PROJ_CORE s i = Some c)
  (at level 66, no associativity, only parsing).
Notation core_exists := E.(Extension.core_exists).
Notation active_csem := E.(Extension.active_csem).
Notation active_proj_core := E.(Extension.active_proj_core).
Notation after_at_external_excl := E.(Extension.after_at_external_excl).
Notation notat_external_handled := E.(Extension.notat_external_handled).
Notation at_external_not_handled := E.(Extension.at_external_not_handled).
Notation ext_upd_at_external := E.(Extension.ext_upd_at_external).
Notation runnable_active := E.(Extension.runnable_active).
Notation runnable_none := E.(Extension.runnable_none).

Lemma all_safe_downward ge n z s m :
  ALL_SAFE ge (S n) z s m -> ALL_SAFE ge n z s m.
Proof. intros INV i CS c H2 H3; eapply safe_downward1; eauto. Qed.

Inductive safety_criteria: Type := SafetyCriteria: forall 
  (*coresteps preserve the invariant*)
  (core_pres: forall ge n z (s: xT) c m CS i s' c' m', 
    ALL_SAFE ge (S n) (s \o z) s m -> 
    ACTIVE s = i -> CORE i is (CS, c) in s -> 
    corestep CS ge c m c' m' -> corestep esem ge s m s' m' -> 
    CORE i is (CS, c') in s' /\ ALL_SAFE ge n (s' \o z) s' m')

  (*corestates satisfying the invariant can corestep*)
  (core_prog: forall ge n z s m i c CS, 
    ALL_SAFE ge (S n) z s m -> 
    ACTIVE s = i -> RUNNABLE ge s = Some i -> CORE i is (CS, c) in s -> 
    exists c', exists s', exists m', 
      corestep CS ge c m c' m' /\ corestep esem ge s m s' m' /\
      CORE i is (CS, c') in s')

  (*"handled" steps respect function specifications*)
  (handled_pres: forall ge s z m c s' m' c' CS ef sig args P Q x, 
    let i := ACTIVE s in CORE i is (CS, c) in s -> 
    at_external CS c = Some (ef, sig, args) -> 
    ListSet.set_mem extfunct_eqdec ef handled = true -> 
    spec_of ef client_sig = (P, Q) -> 
    P x (sig_args sig) args (s \o z) m -> 
    corestep esem ge s m s' m' -> 
    CORE i is (CS, c') in s' -> 
      ((at_external CS c' = Some (ef, sig, args) /\ P x (sig_args sig) args (s' \o z) m' /\
        (forall j, ACTIVE s' = j -> i <> j)) \/
      (exists ret, after_external CS ret c = Some c' /\ Q x (sig_res sig) ret (s' \o z) m')))

  (*"handled" states satisfying the invariant can step or are safely halted;
     core states that stay "at_external" remain unchanged*)

  (handled_prog: forall ge n z s m,
    ALL_SAFE ge n z s m -> RUNNABLE ge s = None -> 
    at_external esem s = None -> 
    (exists s', exists m', corestep esem ge s m s' m' /\ 
      forall i c CS, CORE i is (CS, c) in s -> 
        exists c', CORE i is (CS, c') in s' /\ 
          (forall ef args ef' args', 
            at_external CS c = Some (ef, args) -> 
            at_external CS c' = Some (ef', args') -> c=c')) \/
    (exists rv, safely_halted esem ge s = Some rv))

  (*safely halted threads remain halted*)
  (safely_halted_halted: forall ge s m s' m' i CS c rv,
    CORE i is (CS, c) in s -> safely_halted CS ge c = Some rv -> 
    corestep esem ge s m s' m' -> 
    CORE i is (CS, c) in s')

  (*safety of other threads is preserved when handling one step of blocked
     thread i*)
 
 (handled_rest: forall ge s m s' m' c CS,
    let i := ACTIVE s in CORE i is (CS, c) in s -> 
    ((exists ef, exists args, at_external CS c = Some (ef, args)) \/ 
      exists rv, safely_halted CS ge c = Some rv) -> 
    at_external esem s = None -> 
    corestep esem ge s m s' m' -> 
    (forall CS0 c0 j, i <> j ->  
      (CORE j is (CS0, c0) in s' -> CORE j is (CS0, c0) in s) /\
      (forall n z z', CORE j is (CS0, c0) in s -> 
                      safeN CS0 client_sig ge (S n) (s \o z) c0 m -> 
                      safeN CS0 client_sig ge n (s' \o z') c0 m')))

  (*if the extended machine is at external, then the active thread is at
     external (an extension only implements external functions, it doesn't
     introduce them)*)

  (at_extern_call: forall s ef sig args,
    at_external esem s = Some (ef, sig, args) -> 
    exists CS, exists c, 
      CORE (ACTIVE s) is (CS, c) in s /\ 
      at_external CS c = Some (ef, sig, args))

  (*inject the results of an external call into the extended machine state*)
  (at_extern_ret: forall c z s m z' m' tys args ty ret c' CS ef sig x 
      (P:ext_spec_type esig ef -> list typ -> list val -> Z -> M -> Prop) 
      (Q: ext_spec_type esig ef -> option typ -> option val -> Z -> M -> Prop),
    let i := ACTIVE s in CORE i is (CS, c) in s -> 
    at_external esem s = Some (ef, sig, args) -> 
    spec_of ef esig = (P, Q) -> 
    P x tys args (s \o z) m -> Q x ty ret z' m' -> 
    after_external CS ret c = Some c' -> 
    exists s': xT, 
      z' = s' \o z' /\
      after_external esem ret s = Some s' /\ 
      CORE i is (CS, c') in s')

  (*safety of other threads is preserved when returning from an external 
     function call*)
  (at_extern_rest: forall c z s m z' s' m' tys args ty ret c' CS ef x sig
      (P:ext_spec_type esig ef -> list typ -> list val -> Z -> M -> Prop) 
      (Q: ext_spec_type esig ef -> option typ -> option val -> Z -> M -> Prop),
    let i := ACTIVE s in CORE i is (CS, c) in s -> 
    at_external esem s = Some (ef, sig, args) -> 
    spec_of ef esig = (P, Q) -> 
    P x tys args (s \o z) m -> Q x ty ret z' m' -> 
    after_external CS ret c = Some c' -> 
    after_external esem ret s = Some s' -> 
    CORE i is (CS, c') in s' -> 
    (forall CS0 c0 j, i <> j -> 
      (CORE j is (CS0, c0) in s' -> CORE j is (CS0, c0) in s) /\
      (forall ge n, CORE j is (CS0, c0) in s -> 
                    safeN CS0 client_sig ge (S n) (s \o z) c0 m -> 
                    safeN CS0 client_sig ge n z' c0 m'))),
  safety_criteria.

Lemma safety_criteria_safe : safety_criteria -> safe_extension E.
Proof.
inversion 1; subst; intros ge n; induction n.
intros s m z H1; simpl; auto.
intros s m z H1.
simpl; case_eq (at_external esem s).

(*CASE 1: at_external OUTER = Some _; i.e. _really_ at_external*) 
intros [[ef sig] args] AT_EXT.
destruct (at_external_halted_excl esem ge s) as [H2|H2].
rewrite AT_EXT in H2; congruence.
simpl; rewrite H2.
destruct (at_extern_call s ef sig args AT_EXT) as [CS [c [[H3 H4] H5]]].
generalize H1 as H1'; intro.
specialize (H1 (ACTIVE s) CS c H3 H4).
simpl in H1.
rewrite H5 in H1.
destruct (at_external_halted_excl CS ge c) as [H6|H6].
rewrite H6 in H5; congruence.
rewrite H6 in H1; clear H6.
destruct H1 as [x H1].
destruct H1 as [H7 H8].
generalize (Extension.esem_csem_linkable E); intros Hlink.
assert (H16: IN ef (DIFF client_sig handled)).
 apply in_diff.
 eapply Extension.at_external_client_sig; eauto.
 eapply Extension.at_external_not_handled; eauto.
 auto.
specialize (Hlink ef 
  (ext_spec_pre esig ef) (ext_spec_post esig ef) 
  (ext_spec_pre client_sig ef) (ext_spec_post client_sig ef) H16).
destruct Hlink with (x' := x) 
 (tys := sig_args sig) (args := args) (m := m) (z := (s \o z)) 
 as [x' [H17 H18]]; auto.
exists x'.
erewrite at_external_not_handled; eauto.
split; auto.
erewrite at_external_not_handled; eauto.
intros ret m' z' POST.
destruct (H8 ret m' z') as [c' [H10 H11]].
eapply H18 in POST; eauto.
specialize (at_extern_ret c z s m z' m' (sig_args sig) args (sig_res sig) ret c' CS
 ef sig x' (ext_spec_pre esig ef) (ext_spec_post esig ef)).
hnf in at_extern_ret.
spec at_extern_ret; auto.
spec at_extern_ret; auto.
spec at_extern_ret; auto.
spec at_extern_ret; auto.
spec at_extern_ret; auto.
spec at_extern_ret; auto.
destruct at_extern_ret as [s' [H12 [H13 [H14 H15]]]].
exists s'.
split; auto.
rewrite H12.
eapply IHn.
intros j CSj cj CSEMJ PROJJ.
case_eq (eq_nat_dec (ACTIVE s) j).
(*i=j*)
intros Heq _; rewrite Heq in *.
rewrite CSEMJ in H14; inversion H14; rewrite H1 in *.
rewrite PROJJ in H15; inversion H15; rewrite H6 in *.
unfold proj_zint in H12.
rewrite <-H12.
auto.
(*i<>j*)
intros Hneq _.
specialize (at_extern_rest c z s m z' s' m' (sig_args sig) args (sig_res sig) ret c' CS
  ef x' sig (ext_spec_pre esig ef) (ext_spec_post esig ef)).
hnf in at_extern_rest.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
spec at_extern_rest; auto.
destruct (at_extern_rest CSj cj j Hneq) as [H19 H20].
unfold proj_zint in H12.
rewrite <-H12.
eapply H20; eauto.
destruct H19 as [H21 H22]; auto.
eapply H1'; eauto.

(*CASE 2: at_external OUTER = None; i.e., handled function*)
intros H2.
case_eq (safely_halted esem ge s); auto.
case_eq (RUNNABLE ge s).
(*active thread i*)
intros i RUN.
generalize (runnable_active _ _ RUN) as ACT; intro.
rewrite <-ACT in *.
destruct (active_csem s) as [CS CSEM].
destruct (active_proj_core s) as [c PROJECT].
destruct (core_prog ge n (s \o z) s m i c CS H1 ACT) 
 as [c' [s' [m' [CORESTEP_C [CORESTEP_T [CSEM' PROJECT']]]]]]; auto.
rewrite <-ACT; auto.
rewrite <-ACT; auto.
destruct (core_pres ge n z s c m CS i s' c' m' H1 ACT)
 as [_ INV']; auto.
rewrite <-ACT in *; auto.
exists s'; exists m'; split; [auto|].
apply ext_upd_at_external in CORESTEP_T.
rewrite CORESTEP_T.
eauto.

(*no runnable thread*)
intros RUN.
destruct (active_csem s) as [CS CSEM].
destruct (active_proj_core s) as [c PROJECT].
destruct (handled_prog ge n (s \o z) s m (all_safe_downward H1) RUN H2)
 as [[s' [m' [CORESTEP_T CORES_PRES]]]|[rv SAFELY_HALTED]].
2: intros CONTRA; rewrite CONTRA in SAFELY_HALTED; congruence.
exists s'; exists m'.
split; auto.
erewrite ext_upd_at_external; eauto; eapply IHn.
destruct (runnable_none ge s RUN CSEM PROJECT) 
 as [SAFELY_HALTED|[ef [args AT_EXT]]].

(*subcase A of no runnable thread: safely halted*)
intros j CSj cj CSEMj PROJECTj.
set (i := ACTIVE s) in *.
case_eq (eq_nat_dec i j).
(*i=j*)
intros Heq _; rewrite Heq in *.
destruct (core_exists ge j s m s' m' CORESTEP_T PROJECTj)
 as [c0 PROJECT0].
rewrite PROJECT in PROJECT0; inversion PROJECT0; subst.
rewrite CSEM in CSEMj; inversion CSEMj; rename H4 into H3; rewrite <-H3 in *.
specialize (H1 j CS c0 CSEM PROJECT).
simpl in H1. 
destruct SAFELY_HALTED as [rv SAFELY_HALTED].
destruct (@at_external_halted_excl G cT M D CS ge c0) as [H4|H4]; 
 [|congruence].
destruct n; simpl; auto.
destruct (safely_halted_halted ge s m s' m' j CS c0 rv) as [H6 H7]; auto.
rewrite H7 in PROJECTj; inversion PROJECTj; subst.
rewrite H4, SAFELY_HALTED; auto.
(*i<>j*)
intros Hneq _.
destruct (CORES_PRES i c CS) as [c' [[_ PROJ'] H5]]. 
split; auto.
specialize (handled_rest ge s m s' m' c CS).
hnf in handled_rest.
spec handled_rest; auto.
spec handled_rest; auto.
spec handled_rest; auto.
spec handled_rest; auto.
destruct (handled_rest CSj cj j Hneq) as [H6 H7].
eapply H7 with (z:=z); eauto.
eapply H1; eauto.
destruct (core_exists ge j s m s' m' CORESTEP_T PROJECTj)
 as [c0 PROJECT0].
specialize (H1 j CSj c0 CSEMj PROJECT0).
destruct H6 as [H8 H9].
split; auto.
rewrite H9 in PROJECT0; inversion PROJECT0; subst; auto.

(*subcase B of no runnable thread: at external INNER*)
intros j CSj cj CSEMj PROJECTj.
set (i := ACTIVE s) in *.
case_eq (eq_nat_dec i j).
(*i=j*)
intros Heq _; rewrite Heq in *.
destruct (core_exists ge j s m s' m' CORESTEP_T PROJECTj)
 as [c0 PROJECT0].
rewrite PROJECT in PROJECT0; inversion PROJECT0; subst.
generalize CSEMj as CSEMj'; intro.
rewrite CSEM in CSEMj; inversion CSEMj; rename H4 into H3; rewrite <-H3 in *.
specialize (H1 j CS c0 CSEM PROJECT).
simpl in H1. 
rewrite AT_EXT in H1.
remember (safely_halted CS ge c0) as SAFELY_HALTED.
destruct SAFELY_HALTED. 
solve[destruct ef; elimtype False; auto].
destruct ef as [ef sig].
destruct H1 as [x H1].
destruct H1 as [PRE POST].
specialize (handled_pres ge s z m c0 s' m' cj CS ef sig args
  (ext_spec_pre client_sig ef)
  (ext_spec_post client_sig ef) x).
rewrite Heq in handled_pres.
hnf in handled_pres.
spec handled_pres; auto.
spec handled_pres; auto.
spec handled_pres; auto. 
 eapply notat_external_handled; eauto.
spec handled_pres; auto.
spec handled_pres; auto.
spec handled_pres; auto.
spec handled_pres; auto.
destruct (CORES_PRES j c0 CS) as [c' H4]; [split; auto|].
destruct handled_pres as [[AT_EXT' [PRE' ACT']] | POST'].
(*pre-preserved case*)
destruct H4 as [[H4 H5] H6].
rewrite H5 in PROJECTj; inversion PROJECTj; subst.
specialize (H6 (ef,sig) args (ef,sig) args AT_EXT AT_EXT'); subst.
clear - PRE' POST AT_EXT' H4 H5 HeqSAFELY_HALTED H2 AT_EXT PROJECT CSEMj'.
destruct n; simpl; auto.
rewrite AT_EXT', <-HeqSAFELY_HALTED.
exists x.
split; auto.
intros ret m'' s'' H8.
destruct (POST ret m'' s'' H8) as [c'' [H9 H10]].
exists c''; split; auto.
eapply safe_downward1; eauto.
(*post case*)
destruct H4 as [[H4 H5] H6].
rewrite H5 in PROJECTj; inversion PROJECTj; rename H7 into H1; rewrite <-H1 in *.
destruct POST' as [ret [AFTER_EXT POST']].
generalize (after_at_external_excl j c0 ret H4 AFTER_EXT); intros AT_EXT'.
clear - PRE POST POST' AT_EXT' AFTER_EXT H4 H5 H6 HeqSAFELY_HALTED.
destruct n; simpl; auto.
rewrite AT_EXT'.
case_eq (safely_halted CS ge c'); auto.
destruct (POST ret m' (s' \o z) POST') as [c'' [AFTER_EXT' SAFEN]].
rewrite AFTER_EXT in AFTER_EXT'; inversion AFTER_EXT'; subst.
simpl in SAFEN.
rewrite AT_EXT' in SAFEN.
intros SAFELY_HALTED; rewrite SAFELY_HALTED in SAFEN.
destruct SAFEN as [c3 [m'' [H7 H8]]].
exists c3; exists m''; split; auto.
(*i<>j: i.e., nonactive thread*)
intros Hneq _.
destruct (CORES_PRES i c CS) as [c' [[_ PROJ'] H5]]. 
split; auto.
specialize (handled_rest ge s m s' m' c CS).
hnf in handled_rest.
spec handled_rest; auto.
spec handled_rest; auto.
left; exists ef; exists args; auto.
spec handled_rest; auto.
spec handled_rest; auto.
destruct (handled_rest CSj cj j Hneq) as [H6 H7].
eapply H7 with (z:=z); eauto.
eapply H1; eauto.
destruct (core_exists ge j s m s' m' CORESTEP_T PROJECTj)
 as [c0 PROJECT0].
specialize (H1 j CSj c0 CSEMj PROJECT0).
destruct H6 as [H8 H9].
split; auto.
rewrite H9 in PROJECT0; inversion PROJECT0; subst; auto.
Qed.

End SafetyCriteria.

Section CorestepProperties.
Variables (G xT cT M D Z Zint Zext: Type) 
  (esem: CoreSemantics G xT M D) 
  (csem: nat -> option (CoreSemantics G cT M D))
  (client_sig: ext_sig M Z)
  (esig: ext_sig M Z)
  (handled: list AST.external_function)
  (E: Extension.Sig Zint Zext esem csem client_sig esig handled).

Import Extension.

Definition runnable_corestep := forall ge s m s' m' c CS i,
  runnable E ge s = Some i -> 
  csem i = Some CS -> proj_core E s i = Some c -> 
  corestep esem ge s m s' m' -> 
  exists c', corestep CS ge c m c' m' /\ proj_core E s' i = Some c'.

Definition corestep_active := forall ge c s m c' s' m' CS,
  csem (active E s) = Some CS -> 
  proj_core E s (active E s) = Some c -> 
  corestep CS ge c m c' m' -> 
  corestep esem ge s m s' m' -> 
  (active E s = active E s' /\ proj_core E s' (active E s) = Some c').

Definition corestep_step := forall ge c s m c' m' CS,
  csem (active E s) = Some CS -> 
  proj_core E s (active E s) = Some c -> 
  corestep CS ge c m c' m' -> 
  exists s', corestep esem ge s m s' m' /\ (*conditions somewhat redundant*) 
    active E s = active E s' /\
    proj_core E s' (active E s) = Some c'.

Lemma corestep_step_plus: corestep_step -> 
  forall ge c s m c' m' CS,
  csem (active E s) = Some CS -> 
  proj_core E s (active E s) = Some c -> 
  corestep_plus CS ge c m c' m' -> 
  exists s', corestep_plus esem ge s m s' m' /\ 
    active E s = active E s' /\
    proj_core E s' (active E s) = Some c'.
Proof.
intros H1; intros until CS; intros H2 H3 H4.
inversion H4 as [n H5]; clear H4; revert c c' m m' s H2 H3 H5; induction n. 
intros c c' m m' s H2 H3 H5.
inv H5.
destruct H as [m2 [H H4]].
inv H4.
eapply H1 in H; eauto.
destruct H as [s2 [H [H4 H5]]].
exists s2; split; auto.
exists 0%nat; simpl.
exists s2; exists m'.
split; auto.
intros c c' m m' s H2 H3 H5.
simpl in H5.
destruct H5 as [c2 [m2 [H5 H6]]].
eapply H1 in H5; eauto.
destruct H5 as [s2 [H5 [H7 H8]]].
rewrite H7 in H2, H8.
destruct (IHn c2 c' m2 m' s2 H2 H8) as [s' [H9 [H10 H11]]]; auto.
exists s'.
split3.
inv H9.
exists (S x).
simpl.
exists s2; exists m2; split; auto.
rewrite H7; auto.
rewrite H7, H11; auto.
Qed.

Lemma corestep_step_star: corestep_step -> 
  forall ge c s m c' m' CS,
  csem (active E s) = Some CS -> 
  proj_core E s (active E s) = Some c -> 
  corestep_star CS ge c m c' m' -> 
  exists s', corestep_star esem ge s m s' m' /\ 
    active E s = active E s' /\
    proj_core E s' (active E s) = Some c'.
Proof.
intros H1; intros until CS; intros H2 H3 H4.
inversion H4 as [n H5]; clear H4; revert c c' m m' s H2 H3 H5; induction n. 
intros c c' m m' s H2 H3 H5.
inv H5.
exists s; split; auto.
exists 0%nat; simpl; auto.
intros c c' m m' s H2 H3 H5.
simpl in H5.
destruct H5 as [c2 [m2 [H5 H6]]].
eapply H1 in H5; eauto.
destruct H5 as [s2 [H5 [H7 H8]]].
rewrite H7 in H2, H8.
destruct (IHn c2 c' m2 m' s2 H2 H8) as [s' [H9 [H10 H11]]]; auto.
exists s'.
split3.
inv H9.
exists (S x).
simpl.
exists s2; exists m2; split; auto.
rewrite H7; auto.
rewrite H7, H11; auto.
Qed.

Definition corestep_others := forall ge i s c m s' c' m' (CS: CoreSemantics G cT M D),
  proj_core E s' i = Some c' -> 
  corestep CS ge c m c' m' -> 
  corestep esem ge s m s' m' -> 
  forall j, i<>j -> proj_core E s j = proj_core E s' j.

Definition safely_halted_steps := forall ge s c rv m (CS: CoreSemantics G cT M D),
  proj_core E s (active E s) = Some c -> 
  safely_halted CS ge c = Some rv -> 
  exists s', corestep esem ge s m s' m.

End CorestepProperties.
    
Section LinkableExtension.
Variables (fT: forall X:Type, Type) (cT dT D Z Zint Zext: Type)
  (esem: forall (T: Type) (CS: CompcertCoreSem genv T D), CompcertCoreSem genv (fT T) D) 
  (source: CompcertCoreSem genv cT D) (target: CompcertCoreSem genv dT D)
  (client_sig: ext_sig mem Z) (esig: ext_sig mem Z) (handled: list AST.external_function).

Notation ALL_SAFE := (Extension.all_safe).
Notation PROJ_CORE := (Extension.proj_core).
Infix "\o" := (Extension.zmult) (at level 66, left associativity). 
Notation ACTIVE := (Extension.active).
Notation RUNNABLE := (Extension.runnable).
Notation "'CORE' i 'is' ( CS , c ) 'in' s" := 
  (csem i = Some CS /\ PROJ_CORE s i = Some c)
  (at level 66, no associativity, only parsing).
Notation core_exists := (Extension.core_exists).
Notation active_csem := (Extension.active_csem).
Notation active_proj_core := (Extension.active_proj_core).
Notation after_at_external_excl := (Extension.after_at_external_excl).
Notation notat_external_handled := (Extension.notat_external_handled).
Notation at_external_not_handled := (Extension.at_external_not_handled).
Notation ext_upd_at_external := (Extension.ext_upd_at_external).
Notation runnable_active := (Extension.runnable_active).
Notation runnable_none := (Extension.runnable_none).

Let xT := fT cT.
Let yT := fT dT.

Definition cores (aT:Type) (CS: CompcertCoreSem genv aT D) :=
  fun i:nat => Some (csem CS).

Variable (E1: Extension.Sig Zint Zext (esem source) (cores source) client_sig esig handled).
Variable (E2: Extension.Sig Zint Zext (esem target) (cores target) client_sig esig handled).
Variables (ge: genv) (entry_points: list (val*val*signature)).

Import Sim_inj.

Variable (core_simulation: Forward_simulation_inject D D source target ge ge entry_points).

Definition match_states (cd: core_data core_simulation) (j: meminj) (s1: xT) m1 (s2: yT) m2 :=
  Mem.inject j m1 m2 /\
  ACTIVE E1 s1 = ACTIVE E2 s2 /\
  RUNNABLE E1 ge s1 = RUNNABLE E2 ge s2 /\
  forall i c1, PROJ_CORE E1 s1 i = Some c1 -> 
    exists c2, PROJ_CORE E2 s2 i = Some c2 /\ 
      match_state core_simulation cd j c1 m1 c2 m2.

Inductive linkable_extension: Type := LinkableExtension: forall 
  (runnable_corestep1: runnable_corestep E1)
(*  (runnable_corestep2: runnable_corestep E2)*)
  (corestep_active1: corestep_active E1)
(*  (corestep_active2: corestep_active E2)*)
(*  (corestep_step1: corestep_step E1)*)
  (corestep_step2: corestep_step E2)
  (corestep_others1: corestep_others E1)
(*  (corestep_others2: corestep_others E2)*)
(*  (safely_halted_steps1: safely_halted_steps E1)
  (safely_halted_steps2: safely_halted_steps E2)*)
  (match_mem_inject: forall cd j c1 c2 m1 m2,
    match_state core_simulation cd j c1 m1 c2 m2 -> 
    Mem.inject j m1 m2)
  (inject_extend: forall cd cd' j j' c1 c2 m1 m2 m1' m2',
    match_state core_simulation cd j c1 m1 c2 m2 -> 
    inject_incr j j' -> 
    Mem.inject j' m1' m2' -> 
    match_state core_simulation cd' j' c1 m1' c2 m2')
  (safely_halted_match: forall cd j c1 c2 m1 m1' m2 rv s1 s2 s1',
    match_states cd j s1 m1 s2 m2 -> 
    PROJ_CORE E1 s1 (ACTIVE E1 s1) = Some c1 -> 
    PROJ_CORE E2 s2 (ACTIVE E2 s2) = Some c2 -> 
    safely_halted source ge c1 = Some rv -> 
    corestep (esem source) ge s1 m1 s1' m1' ->  
    safely_halted target ge c2 = Some rv /\
    exists s2', exists m2', exists cd', exists j', 
      inject_incr j j' /\
      Events.inject_separated j j' m1 m2 /\
      corestep (esem target) ge s2 m2 s2' m2' /\
      match_states cd' j' s1' m1' s2' m2'), 
  linkable_extension.

Variable (esig_linkable: linkable_extension).

Program Definition extended_simulation: 
  Forward_simulation_inject D D (esem source) (esem target) ge ge entry_points :=
      Build_Forward_simulation_inject 
      (core_data core_simulation) 
      match_states 
      (core_ord core_simulation)
      _ _ _ _ _ _.
Next Obligation. apply (core_ord_wf core_simulation). Qed.
Next Obligation. 
generalize H0 as H0'; intro.
destruct H0 as [Xinj [X0 [X1 H0]]].
case_eq (RUNNABLE E1 ge st1).
(*Case 1: runnable thread, appeal to core diagram for cores*)
intros n H1.
generalize H1 as H1'; intro.
apply runnable_active in H1.
destruct (active_proj_core E1 st1) as [c1 H2].
rewrite H1 in H2.
assert (exists c1', corestep source ge c1 m1 c1' m1').
 inv esig_linkable.
 unfold runnable_corestep in runnable_corestep1.
 specialize (runnable_corestep1 ge st1 m1 st1' m1' c1 source (ACTIVE E1 st1)).
 destruct runnable_corestep1 as [c1' [H3 H4]]; auto.
 exists c1'; auto.
destruct H3 as [c1' H3].
generalize (core_diagram core_simulation).
intros DIAG.
generalize H0 as H0''; intro.
unfold match_states in H0.
destruct (H0 n c1 H2) as [c2 [H4 H5]].
destruct (DIAG c1 m1 c1' m1' H3 cd c2 j m2 H5) 
 as [c2' [m2' [cd' [j' [H6 [H7 [H8 H9]]]]]]].
destruct H9 as [H9|[H9 H10]].
(*corestep_plus case*)
generalize H9 as H9'.
eapply corestep_step_plus 
 with (esem := esem target) (csem := cores target) (client_sig := client_sig) 
   (esig := esig) (E := E2) (s := st2) in H9; eauto.
destruct H9 as [st2' [H9 [H10 H11]]].
exists st2'; exists m2'; exists cd'; exists j'.
split3; auto.
split; auto.
unfold match_states.
split3; auto.
rewrite <-X0 in H10.
inv esig_linkable; eauto.
rewrite <-H10.
inv esig_linkable.
eapply corestep_active1 in H3; eauto.
destruct H3; eauto.
rewrite <-H1; auto.
split.
admit. (*RUNNABLE*)
intros i c0 H12.
assert (H13: PROJ_CORE E1 st1' n = Some c1'). 
 inv esig_linkable.
 edestruct corestep_active1; eauto.
 unfold cores; auto.
case_eq (eq_nat_dec i n).
(*i=n*)
intros Heq _.
subst.
rewrite H13 in H12.
inv H12.
exists c2'.
rewrite X0; split; auto.
(*i<>n*)
intros Hneq _.
assert (PROJ_CORE E1 st1 i = Some c0). 
 inv esig_linkable.
 erewrite corestep_others1; eauto.
unfold match_states in H0'.
destruct (H0'' i c0 H14) as [c3 [H15 H16]].
exists c3.
split; auto.
 inv esig_linkable.
 admit. (*follows from plus closure of corestep_others and H9', H15*)
inv esig_linkable.
apply inject_extend with (cd := cd) (j := j) (m1 := m1) (m2 := m2); eauto.
inv esig_linkable; auto.
inv esig_linkable.
rewrite <-X0; auto.
(*corestep_star case*)
admit. (*should be similar to corestep_plus*)

(*runnable = None*)
destruct (active_proj_core E1) with (s := st1) as [c1 H1].
destruct (active_csem E1) with (s := st1) as [CS H2].
generalize H2 as H2'; intro.
inv H2'.
intros H3.
apply (runnable_none E1) with (c := c1) (CS := source) (ge := ge) in H2; auto.
destruct H2 as [H2|H2].

(*active thread is safely halted*)
destruct H2 as [rv H2].
unfold match_states in H0.
specialize (H0 (ACTIVE E1 st1) c1 H1).
destruct H0 as [c2 [H0 H4]].
destruct (core_halted core_simulation cd j c1 m1 c2 m2 rv H4 H2) as [H5 H6].
inv esig_linkable.
eapply safely_halted_match with (m1' := m1') in H0'; eauto.
2: rewrite <-X0, H0; eauto.
destruct H0' as [H7 [st2' [m2' [cd' [j' [H8 [H9 [H10 H11]]]]]]]].
exists st2'; exists m2'; exists cd'; exists j'.
split3; auto.
split; auto.
left.
exists 0%nat.
eexists; eexists; split; eauto.
simpl; auto.

(*active thread is at_external*)
destruct H2 as [[ef sig] [args H2]].
unfold match_states in H0.
destruct (H0 (ACTIVE E1 st1) c1 H1) as [c2 [H4 H5]].
destruct (core_at_external core_simulation cd j c1 m1 c2 m2 ef args sig H5 H2)
 as [H6 [H7 [vals2 [H8 [H9 H10]]]]].
admit. (*here we need the user to prove a "core diagram" for external function 
          calls handled by the extension; there must be an appropriate (extended)
          injection to justify each step that handles one of these calls*)
Qed.
Next Obligation. Admitted. (*TODO*)
Next Obligation. Admitted. (*TODO*)
Next Obligation. Admitted. (*TODO*)
Next Obligation. Admitted. (*TODO*)

End LinkableExtension.


