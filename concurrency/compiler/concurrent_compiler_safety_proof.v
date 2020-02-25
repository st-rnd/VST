From Paco Require Import paco.

From mathcomp.ssreflect Require Import ssreflect ssrbool ssrnat ssrfun eqtype.

Require Import compcert.common.Globalenvs.

Require Import VST.concurrency.common.HybridMachineSig.
Import HybridMachineSig.
Set Bullet Behavior "Strict Subproofs".
  
Require Import VST.concurrency.compiler.safety_equivalence.
Require Import VST.concurrency.compiler.concurrent_compiler_simulation.
Require Import VST.concurrency.compiler.concurrent_compiler_simulation_proof.
Require Import VST.concurrency.compiler.sequential_compiler_correct.
Require Import VST.concurrency.compiler.concurrent_compiler_safety.
Require Import VST.concurrency.compiler.concurrent_compiler_simulation_proof.
(*Here the threadpool becomes juicy...*)
Require Import VST.concurrency.compiler.HybridMachine_simulation.
Require Import VST.concurrency.common.HybridMachine.
Require Import Omega.
Require Import VST.concurrency.lib.tactics.
      

(*Clight Machine *)
Require Import VST.concurrency.common.ClightMachine.
(*Asm Machine*)
Require Import VST.concurrency.common.x86_context.


Require Import VST.concurrency.compiler.concurrent_compiler_simulation_definitions.
    

Section Concurrent_Safety.
         Context {CC_correct: CompCert_correctness}
          {Args: ThreadSimulationArguments}.
  (*Import the Clight Hybrid Machine*)
  Import ClightMachine.
  Import DMS.
  (*Import the Asm X86 Hybrid Machine*)
  Import X86Context.

  (*Module ConcurCC_correct:= (Concurrent_correctness CC_correct Args).
  Import ConcurCC_correct.*)


  (*USed to be start_stack*)
  Definition Clight_init_state (p: Clight.program):=
    Clight.initial_state p.
  
  Definition Asm_init_state (p: Asm.program):=
    Asm.initial_state  p.

  Notation valid Sem:=
    (valid dryResources Sem OrdinalPool.OrdinalThreadPool).
  Existing Instance HybridSem.
    Existing Instance dryResources.
    Existing Instance DryHybridMachineSig.
    
  

  Definition opt_init_mem_source (p : Clight.program):=
      (Genv.init_mem (Ctypes.program_of_program p)).
  Definition opt_init_mem_target {F V} (tp:AST.program F V ):=
    (Genv.init_mem tp).
  Definition Clight_ASM_simulation p tp:=
    fun {geS geT} => HybridMachine_simulation'
                   (@ClightConcurSem geS (opt_init_mem_source p))
                   (@AsmConcurSem tp geT (opt_init_mem_target tp))
                   invariant invariant
                   mem_compatible mem_compatible.
  

    Lemma match_valid_equiv:
      forall U (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemanticsForMachines.ClightSem (Clight.globalenv p)) in
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall (m_s m_t : Memory.Mem.mem)
          (j : Values.Val.meminj)
          (C_source : OrdinalPool.t(Sem:=SemSource))
          (C_target : OrdinalPool.t(Sem:=SemTarget)) tr
          (SIM : Clight_ASM_simulation p tp) (cd : index SIM)
          (Hmatch: match_state SIM cd j C_source m_s C_target m_t),
          (valid SemSource) (tr, C_source, m_s) U <-> (valid SemTarget) (tr, C_target, m_t) U.
    Proof.
      intros.
      unfold valid. simpl.
      unfold correct_schedule.
      match_case; try reflexivity.
      destruct SIM; simpl in *.
      unfold unique_Krun; split; intros HH.
      - intros; dup SIM' as Hunique.
        eapply thread_running in Hunique; eauto.
        simpl in *.
        unfold unique_Krun in *.
        eapply Hunique in H; eauto.
      - intros; dup SIM' as Hunique.
        eapply thread_running in Hunique; eauto.
        simpl in *.
        unfold unique_Krun in *.
        eapply Hunique in H; eauto.
    Qed.


    (* Note, unused right now *)
    Lemma thread_stepN_schedule_irr:
      forall (tp : Asm.program)
        (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall  n U U' (c c':  OrdinalPool.t(Sem:=SemTarget)) m m'
           (Hsched: schedPeek U = schedPeek U')
           (HstepN: machine_semantics_lemmas.thread_stepN
                      (AsmConcurSem (opt_init_mem_target tp)) (@the_ge tp) n U c m c' m'),
          machine_semantics_lemmas.thread_stepN
            (AsmConcurSem (opt_init_mem_target tp)) (@the_ge tp) n U' c m c' m'.
    Proof.
      induction n.
      - intros. simpl in *.
        inversion HstepN;
          now auto.
      - intros.
        simpl in HstepN.
        destruct HstepN as [c'' [m'' [Hstep HstepN]]].
        simpl.
        exists c'', m''.
        split; eauto.
        inversion Hstep; subst.
        econstructor; eauto.
        rewrite <- Hsched;
          now auto.
    Qed.
    Set Nested Proofs Allowed.
    Existing Instance HybridCoarseMachine.scheduler.
    Lemma safety_step:
      forall Sem U tr1 C_source m_s,
        U <>  nil ->
        explicit_safety
          HybridMachine.DryHybridMachine.dryResources
          Sem
          (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=Sem))
          HybridMachine.DryHybridMachine.DryHybridMachineSig
          U tr1 C_source m_s ->
        exists st2' m',
          MachStep (U, tr1, C_source) m_s st2' m'.
    Proof.
      intros. inversion H0.
      - hnf in H1.
        unfold halted_machine, schedPeek in *.
        simpl in *. match_case in H1.
        match_case in Heqo.
      - eapply step_equivalence2 in H1. normal_hyp.
        simpl in *. eauto.
        destruct y' as [[? ?] ?].
        simpl in *. unfold MachState.
        exists ((yield U), (seq.cat tr1 x), t), m.
        hnf; simpl; eauto.
      - eapply step_equivalence3 in H1. normal_hyp.
        simpl in *. eauto.
        destruct y' as [[? ?] ?].
        simpl in *. unfold MachState.
        exists ( x', e, t), m.
        hnf; simpl; eauto.
    Qed.
    Lemma safety_inv:
      forall Sem U tr1 C_source m_s,
        U <>  nil ->
        explicit_safety
          HybridMachine.DryHybridMachine.dryResources
          Sem
          (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=Sem))
          HybridMachine.DryHybridMachine.DryHybridMachineSig
          U tr1 C_source m_s ->
        invariant C_source.
    Proof.
      intros.
      exploit safety_step; eauto; intros; normal.
      hnf in H1; simpl in *.
      Existing Instance dryResources.
      Lemma step_invariant:
        forall Sem,
        forall  U tr st m U' tr' st' m',
          @machine_step dryResources Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem)
                        HybridCoarseMachine.DilMem
                        (@DryHybridMachineSig Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem))
                        HybridCoarseMachine.scheduler U tr st m U' tr' st' m' ->
          @invariant Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem) st.
      Proof.
        intros.
        inversion H; eauto;
          try inversion Htstep; eauto.
      Qed.
      eapply step_invariant; eauto.
    Qed.
    
    Lemma safety_cmpt:
      forall Sem U tr1 C_source m,
        U <>  nil ->
        explicit_safety
          HybridMachine.DryHybridMachine.dryResources
          Sem
          (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=Sem))
          HybridMachine.DryHybridMachine.DryHybridMachineSig
          U tr1 C_source m ->
        mem_compatible C_source m.
    Proof.
      Lemma step_cmpt:
        forall Sem,
        forall  U tr st m U' tr' st' m',
          @machine_step dryResources Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem)
                        HybridCoarseMachine.DilMem
                        (@DryHybridMachineSig Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem))
                        HybridCoarseMachine.scheduler U tr st m U' tr' st' m' ->
          @mem_compatible Sem (@OrdinalPool.OrdinalThreadPool dryResources Sem) st m.
      Proof.
        intros.
        inversion H; eauto;
          try inversion Htstep; eauto.
      Qed.
      intros.
      exploit safety_step; eauto; intros; normal.
      hnf in H1; simpl in *.
      intros; eapply step_cmpt; eauto.
    Qed.
    Lemma explicit_safety_step':
      forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemanticsForMachines.ClightSem (Clight.globalenv p)) in
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall (m_s m_t : Memory.Mem.mem)
          (j : Values.Val.meminj)
          (C_source : OrdinalPool.t(Sem:=SemSource))
          (C_target : OrdinalPool.t(Sem:=SemTarget)) tr1 tr2
          (SIM : Clight_ASM_simulation p tp) (cd : index SIM)
          (Hmatch: match_state SIM cd j C_source m_s C_target m_t)
          (Hmatch_events: List.Forall2 (inject_mevent j) tr1 tr2)
          (HsafeS: forall U,
              (valid SemSource) (tr1, C_source, m_s) U ->
              explicit_safety
                HybridMachine.DryHybridMachine.dryResources
                SemSource
                (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
                HybridMachine.DryHybridMachine.DryHybridMachineSig
                U tr1 C_source m_s)
           U (HvalidT: (valid SemTarget) (tr2, C_target, m_t) U),
            explicit_safety
              HybridMachine.DryHybridMachine.dryResources
              SemTarget
              (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              HybridMachine.DryHybridMachine.DryHybridMachineSig
              U tr2 C_target m_t.
    Proof.
      intros.
      eapply coinductive_safety.exp_safety_paco_correct.
      eapply coinductive_safety.safetyN_equivalence.
      simpl; now auto.
      eapply coinductive_safety.speach_therapy with (cd := cd).
      now eapply (core_ord_wf SIM).
      generalize dependent m_t.
      generalize dependent C_target.
      generalize dependent tr2.
      generalize dependent tr1.
      generalize dependent U.
      generalize dependent m_s.
      generalize dependent j.
      generalize dependent C_source.
      generalize dependent cd.
      pcofix HsafeT.
      intros.
      assert (HvalidS: (valid SemSource) (tr1, C_source, m_s) U)
        by (eapply match_valid_equiv; eauto).
      specialize (HsafeS U HvalidS).
      inversion HsafeS as [HhaltedS | stS' Hstep CIH | U' stS' Hstep CIH].
      - (* halted case *)
        pfold.
        econstructor 1.
        simpl in *.
        remember (machine_semantics.conc_halted (ClightConcurSem (opt_init_mem_source p)) U
                                                C_source) as v1 eqn:Hhalted.
        symmetry in Hhalted.
        simpl in Hhalted.
        unfold halted_machine in *.
        simpl in *.
        destruct (schedPeek U);
          now auto.
      - (* internal step case *)
        destruct stS' as [[evS C_source'] m_s'].
        simpl in Hstep.
        pose proof Hstep as HstepS.
        eapply (thread_diagram SIM) with (sge := Clight.globalenv p) (tge := the_ge) in Hstep;
          eauto.
        destruct Hstep as (C_target' & m_t' &cd' & j'
                           & Hmatch' &Hevs' &HstepT& Hincr).
        destruct HstepT as [HstepT | [HstepT Hdec]].
        + (* Step Plus case *)
          destruct HstepT as [n HstepN].
          pfold.
          econstructor 2 with (y' := (tr2, C_target', m_t')) (n:=n); eauto.
          * clear CIH HsafeT HvalidT HvalidS HsafeS Hmatch' HstepS Hmatch.
            generalize dependent m_t'.
            generalize dependent C_target'.
            generalize dependent m_t.
            generalize dependent C_target.
            induction n.
            ** intros.
               simpl in HstepN.
               destruct HstepN as [? [? [? Heq]]].
               inversion Heq; subst.
               econstructor 2 with (_y := (tr2, C_target', m_t')); simpl; eauto.
               econstructor 1.
               auto.
            ** intros.
               simpl in HstepN.
               destruct HstepN as [C_target'' [m_t'' [HstepT' HstepN]]].
               econstructor 2 with (_y := (tr2, C_target'', m_t'')); simpl; eauto.
          * intros.
            simpl in H.
            right.
            eapply HsafeT; try apply Hevs'; eauto.
            intros.
            eapply explicit_safety_trace_irr with (tr := evS).
            eapply CIH.
            simpl.
            now eauto.
        + (* Step Star case *)
          eapply paco3_fold; eauto.
          destruct HstepT as [n HstepN].
          destruct n.
          * simpl in HstepN; inversion HstepN; subst.
            econstructor 4; eauto.
            right.
            eapply HsafeT; try apply Hevs'; eauto.
            intros.
            eapply explicit_safety_trace_irr with (tr := evS).
            eapply CIH.
            simpl.
            now eauto.
          * econstructor 2 with (y' := (tr2, C_target', m_t')) (n:=n); eauto.
            (* this part here is exactly the same as the step plus case and I can 
               probably factor into a lemma,
               but right now I am just trying to get things to work *)
            ** clear CIH HsafeT HvalidT HvalidS HsafeS Hmatch' HstepS Hmatch.
               generalize dependent m_t'.
               generalize dependent C_target'.
               generalize dependent m_t.
               generalize dependent C_target.
               induction n.
               *** intros.
                   simpl in HstepN.
                   destruct HstepN as [? [? [? Heq]]].
                   inversion Heq; subst.
                   econstructor 2 with (_y := (tr2, C_target', m_t')); simpl; eauto.
                   econstructor 1.
                   auto.
               *** intros.
                   simpl in HstepN.
                   destruct HstepN as [C_target'' [m_t'' [HstepT' HstepN]]].
                   econstructor 2 with (_y := (tr2, C_target'', m_t'')); simpl; eauto.
            ** intros.
               right.
               eapply HsafeT; try apply Hevs'; eauto.
               intros.
               eapply explicit_safety_trace_irr with (tr := evS); eauto.
               eapply CIH; eauto.
      - (* external step case*)
        destruct stS' as [[evS C_source'] m_s'].
        simpl in Hstep.
        pose proof Hstep as HstepS.
        eapply (machine_diagram SIM) with (sge := Clight.globalenv p) (tge := the_ge) in Hstep;
          eauto.
        + destruct Hstep as
              (tr2' & C_target' & m_t' & cd' &
               j' & Hmatch' &Hevs' & HstepT &Hincr). 
          simpl in HstepT.
          pfold.
          econstructor 3 with (y' := (tr2', C_target', m_t'));
            eauto.
        + (* prove that inv is satisfied. *)
          simpl in CIH.
          exploit @step_equivalence3; eauto; intros HMachStep.
          normal.
          exploit Step_exists_valid; eauto; try eapply H0.
          intros HH; normal.
          eapply safety_inv; eauto.
          eapply CIH; eauto.
        + simpl in CIH.
          exploit @step_equivalence3; eauto; intros HMachStep.
          normal.
          exploit Step_exists_valid; eauto; try eapply H0.
          intros HH; normal.
          eapply safety_cmpt; eauto.
          eapply CIH; eauto.

          
        Unshelve. all:auto.
    Qed.
    Lemma explicit_safety_step:
    forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemanticsForMachines.ClightSem (Clight.globalenv p)) in
         let SemTarget:= @X86Sem tp asm_genv_safety in
         forall (U : schedule) (m_s m_t : Memory.Mem.mem)
           (j : Values.Val.meminj) (c : Asm.state)
           (C_source : OrdinalPool.t(Sem:=SemSource))
           (C_target : OrdinalPool.t(Sem:=SemTarget)) tr1 tr2
           (SIM : Clight_ASM_simulation p tp) (cd : index SIM)
           (Hmatch_events: List.Forall2 (inject_mevent j) tr1 tr2),
           match_state SIM cd j C_source m_s C_target
                       m_t ->
           (forall U,
               (valid SemSource) (tr1, C_source, m_s) U ->
               explicit_safety
                 HybridMachine.DryHybridMachine.dryResources
                 SemSource
                 (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
                 HybridMachine.DryHybridMachine.DryHybridMachineSig
                 U tr1 C_source m_s) ->
           forall U,
          (valid SemTarget) (tr2, C_target, Asm.get_mem c) U ->
            explicit_safety
              HybridMachine.DryHybridMachine.dryResources
              SemTarget
              (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              HybridMachine.DryHybridMachine.DryHybridMachineSig
              U tr2 C_target m_t.
    Proof.
      intros. eapply explicit_safety_step'; eauto.
    Qed.
    
    Lemma Clight_finite_branching:
      let ClightSem:= ClightSemanticsForMachines.ClightSem in 
            forall (p : Clight.program)
                   (x : kstate dryResources (ClightSem (Clight.globalenv p)) OrdinalPool.OrdinalThreadPool),
              safety.finite_on_x
                (safety.possible_image
                   (fun
                       (x0 : kstate dryResources (ClightSem (Clight.globalenv p))
                                    OrdinalPool.OrdinalThreadPool) (y : schedule)
                       (x' : kstate dryResources (ClightSem (Clight.globalenv p))
                                    OrdinalPool.OrdinalThreadPool) =>
                       exists y' : schedule,
                         kstep dryResources (ClightSem (Clight.globalenv p)) OrdinalPool.OrdinalThreadPool
                               DryHybridMachineSig x0 y x' y') (valid (ClightSem (Clight.globalenv p))) x).
    Proof.
      simpl. intros. destruct x as [[? ?] ?].
      unfold kstep; simpl.
      
    Admitted.
    
    Lemma csafety_step:
      forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemanticsForMachines.ClightSem (Clight.globalenv p)) in
         let SemTarget:= @X86Sem tp asm_genv_safety in
         forall (U : schedule) (init_mem_source' : Memory.Mem.mem)
             (j : Values.Val.meminj) (c : Asm.state)
             (C_source : OrdinalPool.t(Sem:=SemSource))
             (C_target : OrdinalPool.t) tr1 tr2
             (SIM : Clight_ASM_simulation p tp) (cd : index SIM)
         (Hmatch_events: List.Forall2 (inject_mevent j) tr1 tr2),
        match_state SIM cd j C_source init_mem_source' C_target
                    (Asm.get_mem c) ->
        (forall (n : nat) U,
            (valid SemSource) (tr1, C_source, init_mem_source') U ->
            HybridCoarseMachine.csafe(Sem:=SemSource)
                                     (resources:=HybridMachine.DryHybridMachine.dryResources)
                                     (ThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
      (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
                                     (U, tr1, C_source)
                                     init_mem_source' n) ->
        forall (n : nat) U ,
          (valid SemTarget) (tr2, C_target, Asm.get_mem c) U ->
          HybridCoarseMachine.csafe (Sem:=SemTarget)
                                     (resources:=HybridMachine.DryHybridMachine.dryResources)
                                     (ThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
      (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
                                     (U, tr2, C_target)
                                     (Asm.get_mem c) n.
    Proof.
      intros until n.
      eapply explicit_safety_csafe; eauto.      
      eapply explicit_safety_step; eauto.
      eapply csafe_explicit_safety.
      + eapply Clight_finite_branching.
      + eapply H0. 
    Qed.



    (** for the initial state, it's enough to prove csafety for the valid schedules,
        we can derive safety for all others. *)
    Lemma initial_csafe_all_schedule:
      forall  prog asm_genv_safety tr c m r,
        let SemTarget:= @X86Sem prog asm_genv_safety in
        let tp:=OrdinalPool.mkPool (Krun c) r in
        (forall U (n : nat),
            (valid SemTarget) (tr, tp, m) U ->
            HybridCoarseMachine.csafe
              (ThreadPool:=threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
              (U, nil,
               OrdinalPool.mkPool
                 (Krun c) r) m n)  ->
        forall U (n : nat),
          HybridCoarseMachine.csafe
            (ThreadPool:=threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
            (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
            (U, nil,
             OrdinalPool.mkPool (Krun c) r) m n.
    Proof.
      intros.
      revert U.
      induction n; try solve[econstructor].
      intros U.
      destruct U as [|i U]; [|destruct i].
      - econstructor; eauto.
      - eapply H.
        unfold safety_equivalence.valid, correct_schedule; simpl.
        intros ????.
        simpl in cnti.
        unfold OrdinalPool.containsThread in cnti; simpl in cnti.
        clear - cnti.
        eapply semax_invariant.ssr_leP_inv in cnti.
        destruct j; simpl; [auto| omega].
      - intros.
        eapply HybridCoarseMachine.CoreSafe; simpl.
        replace (i.+1 :: U)%list with
            (@yield HybridCoarseMachine.scheduler (i.+1 :: U)%list) by
            reflexivity.
        eapply schedfail; simpl.
        * reflexivity.
        * left; unfold OrdinalPool.containsThread; simpl.
          intros LEQ; eapply semax_invariant.ssr_leP_inv in LEQ.
          omega.
        * assert ((valid SemTarget) (tr, tp, m) (cons 0 nil) ).
          { subst tp; auto.
          unfold safety_equivalence.valid, correct_schedule; simpl.
          intros ????.
          simpl in cnti.
          unfold OrdinalPool.containsThread in cnti; simpl in cnti.
          clear - cnti.
          eapply semax_invariant.ssr_leP_inv in cnti.
          destruct j; simpl; [auto| omega]. }
          apply (H _ 1) in H0.
          { !goal (invariant _).

            inversion H0; subst.
            - inversion H1.
            - eapply step_invariant, Hstep.
            - eapply step_invariant, Hstep. }
              
        *  assert ((valid SemTarget) (tr, tp, m) (cons 0 nil) ).
          { subst tp; auto.
          unfold safety_equivalence.valid, correct_schedule; simpl.
          intros ????.
          simpl in cnti.
          unfold OrdinalPool.containsThread in cnti; simpl in cnti.
          clear - cnti.
          eapply semax_invariant.ssr_leP_inv in cnti.
          destruct j; simpl; [auto| omega]. }
          apply (H _ 1) in H0.
          { !goal (mem_compatible _ _).

            inversion H0; subst.
            - inversion H1.
            - eapply step_cmpt, Hstep.
            - eapply step_cmpt, Hstep. }
        * eapply IHn.
    Qed.
    
    Lemma ConcurrentCompilerSafety:
      CompCert_compiler C_program = Some Asm_program ->
      forall (asm_genv_safety : Asm_core.safe_genv (@the_ge Asm_program))
        (Hextern: single_thread_simulation_proof.Asm_externals_have_events Asm_g),
        let SemSource:= (ClightSemanticsForMachines.ClightSem
                           (Clight.globalenv C_program)) in
        let SemTarget:= @X86Sem Asm_program asm_genv_safety in
        concurrent_simulation_safety_preservation
          (Genv.init_mem (Ctypes.program_of_program C_program))
          (Genv.init_mem Asm_program)
          (SemSource:= SemSource)
          (SourceThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
          (SourceMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
          (SemTarget :=  SemTarget)
          (TargetThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
          (TargetMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
    .
      unfold concurrent_simulation_safety_preservation; intros.
      (* destruct H0. simpl in H2.
         unfold init_mach in *.
      *)
      pose proof (ConcurrentCompilerCorrectness Asm_program Hextern H asm_genv_safety)
        as SIM.
      unfold ConcurrentCompilerCorrectness_specification in SIM.
      (*Construct the initial state*)
      exploit HybridMachine_simulation.initial_setup.
      { eapply SIM. }
      { match goal with
        [H: machine_semantics.initial_machine ?SEM1 _ _ _ _ _ _ |-
         machine_semantics.initial_machine ?SEM2 _ _ _ _ _ _] =>
        replace SEM2 with SEM1 by (rewrite H0; reflexivity)
      end.
        eapply H1. }
      intro HH; destruct HH as (j&cd&t_mach_state&t_mem&t_mem'&r2&(INIT_mem & INIT)&?).
      assert(INIT':= INIT).
      destruct r2; try solve[inversion INIT'].
      destruct INIT' as (c&?&?).
      subst t_mach_state; simpl in *.
      do 3 eexists; repeat split; eauto.
      eapply INIT.
      
      destruct H4 as (H21 & H22); subst.
      clear INIT H21.

      (* Now, we strip out the scheudle, until it starts with 1*)
      eapply initial_csafe_all_schedule.
      intros; eapply csafety_step; eauto.
      eapply H3.

      Unshelve.
      { eapply DryHybridMachineSig. }
      { eapply DryHybridMachineSig. }

    Qed.

    Definition SemSource:= (ClightSemanticsForMachines.ClightSem
                           (Clight.globalenv C_program)).
    Definition SemTarget asm_genv_safety:= @X86Sem Asm_program asm_genv_safety.
    Definition SourceMachineSig:= 
         (@DryHybridMachineSig SemSource (@OrdinalPool.OrdinalThreadPool dryResources SemSource)).
    Definition TargetMachineSig ags:= 
      (@DryHybridMachineSig (SemTarget ags) (@OrdinalPool.OrdinalThreadPool dryResources (SemTarget ags))).

    Definition SourceThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource).
    Definition TargetThreadPool ags:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=(SemTarget ags)).
          
    Notation resources:= HybridMachine.DryHybridMachine.dryResources.
    
  Definition SourceHybridMachine:=
    @HybridCoarseMachine.HybridCoarseMachine
      resources SemSource
      SourceThreadPool SourceMachineSig.
  Definition TargetHybridMachine ags:=
    @HybridCoarseMachine.HybridCoarseMachine resources (SemTarget ags) (TargetThreadPool ags) (TargetMachineSig ags).
  
  Definition SourceSemantics:= (fun m => ConcurMachineSemantics(HybridMachine:=SourceHybridMachine) m).
  Definition TargetSemantics ags:= (fun m => ConcurMachineSemantics(HybridMachine:=TargetHybridMachine ags) m).
  
    (* Ok this lemma is not used right now.
       As it stands, it has several problems, 
       the order of the schedule in the conclusion doesn't match the order in
       concurrent_simulation_safety_preservation  
       Have to reconsider!

      

 Lemma clean_theorem_equivalence:
      forall asm_genv_safety : Asm_core.safe_genv (@the_ge Asm_program),
        let SemSource:= (ClightSemanticsForMachines.ClightSem
                           (Clight.globalenv C_program)) in
        let SemTarget:= @X86Sem Asm_program asm_genv_safety in
        concurrent_simulation_safety_preservation
          (Genv.init_mem (Ctypes.program_of_program C_program))
          (Genv.init_mem Asm_program)
          (SemSource:= SemSource)
          (SourceThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
          (SourceMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
          (SemTarget :=  SemTarget)
          (TargetThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
          (TargetMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig) ->
      main_safety_preservation SourceSemantics (TargetSemantics asm_genv_safety).
      Proof.
        unfold main_safety_preservation,
        concurrent_simulation_safety_preservation.
        intros * HSafety1 Asm_prog C_prog * Hinit Hsafe.

        (*
        (* pull the schedule out of the existensial *)
        cut (  forall (U : schedule),
               exists (tgt_tp : ThreadPool.t) (tgt_m' : Memory.Mem.mem),
                initial_machine_state (TargetSemantics asm_genv_safety) tgt_m' tgt_tp ->
                forall (n : nat),
                  HybridCoarseMachine.csafe (U, empty_trace, tgt_tp) tgt_m' n).
        { clear. intros. destruct (H nil) as (tp&m&?).
          exists tp, m. intros HH n U.
          destruct (H U) as (tp'&m'&H0').
          eapply H0'. *)
          
        inversion Hinit; subst; clear Hinit.
        simpl in H0; unfold init_machine'' in H0.
        destruct H0 as (_ & Hinit_mach); simpl in *.
        dup Hinit_mach as Hinit_save.
        destruct Hinit_mach as (c&(Hinit&Hmem)&HH); simpl in *.
        assert (c = src_tp0).
        { clear - HH; inversion HH.
          eapply Eqdep.EqdepTheory.inj_pair2 in H0.
          eapply FunctionalExtensionality.equal_f in H0.
          - inversion H0; auto.
          - econstructor; auto.
        }
        subst c; clear HH.

        do 2 eexists; intros.

        inversion H; subst; simpl in *.
        hnf in H1. destruct H1 as [_ Hinit_mach].
        dup Hinit_mach as Hinit_save'.
        destruct Hinit_mach as (c_tgt&(Hinit_tgt&Hmem_tgt)&HH_tgt); simpl in *.
        
        inversion Hinit; subst; simpl in *.
        exploit HSafety1.
        - shelve. (* SHELVED: init memory*)
        - econstructor; simpl; eauto.
        - eapply Hsafe.
        - (* The equivalence *)
          instantiate(3:=U0).
          clear.
          intros HH; normal_hyp.
          
      Adm itted.*)      

    
End Concurrent_Safety.
