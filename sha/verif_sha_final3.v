Require Import floyd.proofauto.
Require Import sha.sha.
Require Import sha.SHA256.
Require Import sha.spec_sha.
Require Import sha.sha_lemmas.
Require Import sha.verif_sha_final2.
Local Open Scope logic.

Definition sha_final_epilog :=
              (Ssequence
                          (Scall None
                            (Evar _sha256_block_data_order (Tfunction
                                 (Tcons(tptr t_struct_SHA256state_st)
                                   (Tcons (tptr tvoid) Tnil))
                                 tvoid cc_default))
                            ((Etempvar _c (tptr t_struct_SHA256state_st)) ::
                             (Etempvar _p (tptr tuchar)) :: nil))
                          (Ssequence
                            (Sassign
                              (Efield
                                (Ederef
                                  (Etempvar _c (tptr t_struct_SHA256state_st))
                                  t_struct_SHA256state_st) _num tuint)
                              (Econst_int (Int.repr 0) tint))
                            (Ssequence
                              (Scall None
                                (Evar _memset (Tfunction
                                                (Tcons (tptr tvoid)
                                                  (Tcons tint
                                                    (Tcons tuint Tnil)))
                                                (tptr tvoid) cc_default))
                                ((Etempvar _p (tptr tuchar)) ::
                                 (Econst_int (Int.repr 0) tint) ::
                                 (Ebinop Omul (Econst_int (Int.repr 16) tint)
                                   (Econst_int (Int.repr 4) tint) tint) ::
                                 nil))
           (Ssequence final_loop (Sreturn None))))).

Lemma sha_final_part3:
forall (Espec : OracleKind) (md c : val) (shmd : share)
  (hashed lastblock: list int) msg kv
 (Hshmd: writable_share shmd),
 (LBLOCKz | Zlength hashed) ->
 Zlength lastblock = LBLOCKz ->
 generate_and_pad msg = hashed++lastblock ->
semax
  (initialized _cNl (initialized _cNh Delta_final_if1))
  (PROP  (Forall isbyteZ (intlist_to_Zlist lastblock))
   LOCAL  (temp _p (field_address t_struct_SHA256state_st [StructField _data] c);
           temp _md md; temp _c c;
           gvar _K256 kv)
   SEP 
   (data_at Tsh t_struct_SHA256state_st
       (map Vint (hash_blocks init_registers hashed),
        (Vundef, (Vundef, (map Vint (map Int.repr (intlist_to_Zlist lastblock)), Vundef)))) c;
    K_vector kv;
    memory_block shmd 32 md))
  sha_final_epilog
  (function_body_ret_assert tvoid
     (PROP  ()
      LOCAL ()
      SEP  (K_vector kv;
        data_at_ Tsh t_struct_SHA256state_st c;
        data_block shmd (SHA_256 msg) md))).
Proof.
  intros.
  Time normalize.
  unfold sha_final_epilog.
  abbreviate_semax.
  Time unfold_data_at 1%nat. 
  Time forward_call (* sha256_block_data_order (c,p); *)
    (hashed, lastblock, c,
      field_address t_struct_SHA256state_st [StructField _data] c,
       Tsh, kv).
  {
    unfold data_block. simpl.
    Time entailer!. autorewrite with sublist.
    rewrite H0.
    rewrite field_at_data_at with (gfs := [StructField _data]).
    Time cancel. 
  }
  unfold data_block.
  simpl. rewrite prop_true_andp by apply isbyte_intlist_to_Zlist.
  rewrite <- H1.
  Time forward. (* c->num=0; *)
  Time forward_call (* memset (p,0,SHA_CBLOCK); *) 
    (Tsh, (field_address t_struct_SHA256state_st [StructField _data] c), 64%Z, Int.zero)
    vret.
  {
    replace (Zlength (intlist_to_Zlist lastblock)) with 64
        by (rewrite Zlength_intlist_to_Zlist, H0; reflexivity).
    Time saturate_local.
    change (memory_block Tsh 64) with (memory_block Tsh (sizeof cenv_cs (tarray tuchar 64))).
    rewrite memory_block_data_at_ by auto.
    Time cancel.
  }
  change Delta with
    (initialized _cNl (initialized _cNh Delta_final_if1)).
  eapply semax_pre; [ | apply final_part4; auto].
  + Time unfold_data_at 2%nat.
    rewrite field_at_data_at with (gfs := [StructField _data]) by reflexivity.
    Time entailer!.
    apply derives_refl. (* this should have cancelled *)
  + apply length_hash_blocks; auto.
    rewrite H1.
    apply divide_length_app; auto.
    rewrite H0. apply Z.divide_refl.
Time Qed.

Lemma array_at_memory_block:
 forall {cs: compspecs} sh t gfs lo hi v p n,
  sizeof cenv_cs (nested_field_array_type t gfs lo hi) = n ->
  array_at sh t gfs lo hi v p |-- 
  memory_block sh n (field_address0 t (ArraySubsc lo :: gfs) p).
Proof.
intros.
rewrite  array_at_data_at.
normalize.
unfold at_offset.
rewrite field_address0_offset by auto.
subst n.
apply data_at_memory_block.
Qed.

Hint Extern 2 (array_at _ _ _ _ _ _ _ |-- memory_block _ _ _) =>
   (apply array_at_memory_block; reflexivity) : cancel.

Lemma final_part2:
forall (Espec : OracleKind) (hashed : list int) (md c : val) (shmd : share) kv,
writable_share shmd ->
name _md ->
name _c ->
name _p ->
name _n ->
name _cNl ->
name _cNh ->
forall bitlen (dd : list Z),
(LBLOCKz | Zlength hashed) ->
((Zlength hashed * 4 + Zlength dd)*8)%Z = bitlen ->
(Zlength dd < CBLOCKz) ->
 (Forall isbyteZ dd) ->
forall (hashed': list int) (dd' : list Z) (pad : Z),
 (Forall isbyteZ dd') ->
 (pad=0%Z \/ dd'=nil) ->
(Zlength dd' + 8 <= CBLOCKz)%Z ->
(0 <= pad < 8)%Z ->
(LBLOCKz | Zlength hashed') ->
intlist_to_Zlist hashed' ++ dd' =
intlist_to_Zlist hashed ++ dd ++ [128%Z] ++ list_repeat (Z.to_nat pad) 0 ->
semax Delta_final_if1
  (PROP  ()
      LOCAL 
      (temp _p 
         (field_address t_struct_SHA256state_st [ArraySubsc (CBLOCKz - 8); StructField _data] c);
      temp _n (Vint (Int.repr (Zlength dd'))); 
      temp _md md; temp _c c; gvar _K256 kv)
      SEP 
      (field_at Tsh t_struct_SHA256state_st [StructField _data]
           (map Vint (map Int.repr dd') ++
            list_repeat (Z.to_nat (CBLOCKz - 8 - Zlength dd'))
              (Vint Int.zero) ++ list_repeat (Z.to_nat 8) Vundef) c;
      field_at Tsh t_struct_SHA256state_st [StructField _num] Vundef c;
      field_at Tsh t_struct_SHA256state_st [StructField _Nh] (Vint (hi_part bitlen)) c;
      field_at Tsh t_struct_SHA256state_st [StructField _Nl] (Vint (lo_part bitlen)) c;
      field_at Tsh t_struct_SHA256state_st [StructField _h]
          (map Vint (hash_blocks init_registers hashed')) c;
      K_vector kv;
      memory_block shmd 32 md))
  (Ssequence
     (Sset _cNh
        (Efield
           (Ederef (Etempvar _c (tptr t_struct_SHA256state_st))
              t_struct_SHA256state_st) _Nh tuint))
     (Ssequence
        (Ssequence
           (Scall None
              (Evar ___builtin_write32_reversed
                 (Tfunction (Tcons (tptr tuint) (Tcons tuint Tnil)) tvoid cc_default))
              [Ecast (Etempvar _p (tptr tuchar)) (tptr tuint);
              Etempvar _cNh tuint])
           (Sset _p
              (Ebinop Oadd (Etempvar _p (tptr tuchar))
                 (Econst_int (Int.repr 4) tint) (tptr tuchar))))
        (Ssequence
           (Sset _cNl
              (Efield
                 (Ederef (Etempvar _c (tptr t_struct_SHA256state_st))
                    t_struct_SHA256state_st) _Nl tuint))
           (Ssequence
              (Ssequence
                 (Scall None
                    (Evar ___builtin_write32_reversed
                       (Tfunction (Tcons (tptr tuint) (Tcons tuint Tnil))
                          tvoid cc_default))
                    [Ecast (Etempvar _p (tptr tuchar)) (tptr tuint);
                    Etempvar _cNl tuint])
                 (Sset _p
                    (Ebinop Oadd (Etempvar _p (tptr tuchar))
                       (Econst_int (Int.repr 4) tint) (tptr tuchar))))
              (Ssequence
                 (Sset _p
                    (Ebinop Osub (Etempvar _p (tptr tuchar))
                       (Ebinop Omul (Econst_int (Int.repr 16) tint)
                          (Econst_int (Int.repr 4) tint) tint) (tptr tuchar)))
                 (Ssequence
                    (Scall None
                       (Evar _sha256_block_data_order
                          (Tfunction
                             (Tcons (tptr t_struct_SHA256state_st)
                                (Tcons (tptr tvoid) Tnil)) tvoid cc_default))
                       [Etempvar _c (tptr t_struct_SHA256state_st);
                       Etempvar _p (tptr tuchar)])
                    (Ssequence
                       (Sassign
                          (Efield
                             (Ederef
                                (Etempvar _c (tptr t_struct_SHA256state_st))
                                t_struct_SHA256state_st) _num tuint)
                          (Econst_int (Int.repr 0) tint))
                       (Ssequence
                             (Scall None
                                (Evar _memset
                                   (Tfunction
                                      (Tcons (tptr tvoid)
                                         (Tcons tint (Tcons tuint Tnil)))
                                      (tptr tvoid) cc_default))
                                [Etempvar _p (tptr tuchar);
                                Econst_int (Int.repr 0) tint;
                                Ebinop Omul (Econst_int (Int.repr 16) tint)
                                  (Econst_int (Int.repr 4) tint) tint])
                          (Ssequence
                             final_loop
                             (Sreturn None))))))))))
  (function_body_ret_assert tvoid
     (PROP  ()
      LOCAL ()
      SEP  (K_vector kv;
        data_at_ Tsh t_struct_SHA256state_st c;
        data_block shmd
          (intlist_to_Zlist
             (hash_blocks init_registers
                (generate_and_pad
                   (intlist_to_Zlist hashed ++ dd))))
          md))).
Proof.
  intros Espec hashed md c shmd kv H md_ c_ p n cNl cNh
  bitlen dd H4 H7 H3 DDbytes hashed' dd' pad
  DDbytes' PAD H0 H1 H2 H5(* Pofs*).
  abbreviate_semax.
  pose (hibytes := map force_int (map Vint (map Int.repr (intlist_to_Zlist [hi_part bitlen])))).
  pose (lobytes := map force_int (map Vint (map Int.repr (intlist_to_Zlist [lo_part bitlen])))).
  assert_PROP (field_compatible t_struct_SHA256state_st [StructField _data] c).
    Time entailer!. (*2.3*) rename H6 into FC.

  Time forward. (* cNh=c->Nh; *) (*3.5*)
  
  match goal with |- semax _ (PROPx _ (LOCALx _ (SEPx (?A :: _)))) _ _ =>
    pattern A;
    match goal with |- ?F A => set (GOAL := F) end
  end.
  erewrite field_at_Tarray; try reflexivity;
   [ | apply compute_legal_nested_field_spec'; repeat constructor; auto; omega
   | omega].
  rewrite <- app_ass.
   change (Z.to_nat 8) with (Z.to_nat 4 + Z.to_nat 4)%nat.
   rewrite <- list_repeat_app.
   rewrite (split2_array_at _ _ _ 0 56) by omega.
   rewrite (split2_array_at _ _ _ 56 60) by omega.
   assert (CBZ: CBLOCKz = 64) by reflexivity.
   Time autorewrite with sublist. (*11.5*)
   clear CBZ; subst GOAL. cbv beta.
   Time Intros.  (* to flatten the SEP *)
  Time forward_call (* (void)HOST_l2c(cNh,p); *)
     (field_address0 t_struct_SHA256state_st
                    [ArraySubsc 56; StructField _data] c,
      Tsh, hibytes). (*9*)
  apply prop_right; repeat constructor; hnf; simpl.
  unfold hibytes.
  rewrite (nth_big_endian_integer 0 [hi_part bitlen] (hi_part bitlen)) at 1 by reflexivity.
  reflexivity.

  rewrite field_address_offset by auto.
  rewrite field_address0_offset by auto with field_compatible.
  destruct c_; try contradiction; simpl; auto.
  split; auto.
  subst hibytes; clear; compute; congruence.
  Time forward. (* p += 4; *) (*11 secs*)
  Time forward. (* cNl=c->Nl; *) (*12*)
  Time forward_call (* (void)HOST_l2c(cNl,p); *)
    (field_address0 t_struct_SHA256state_st
                    [ArraySubsc 60; StructField _data] c,
     Tsh, lobytes). (*8.8*)
  apply prop_right; repeat constructor; hnf; simpl.
  unfold lobytes.
  rewrite (nth_big_endian_integer 0 [lo_part bitlen] (lo_part bitlen)) at 1 by reflexivity.
  reflexivity.

  pose proof CBLOCKz_eq.
  rewrite field_address0_offset by auto with field_compatible.
  rewrite field_address_offset by auto with field_compatible.
  destruct c_; try contradiction; simpl; auto.
  normalize.

  split; auto.   compute; congruence.

  replace_SEP 0 (array_at Tsh t_struct_SHA256state_st [StructField _data] 60 64
                           (map Vint lobytes) c). {
  clearbody lobytes.
  rewrite array_at_data_at' by auto with field_compatible.
  Time entailer!. (*2.4 -> 2.0 *)
}
  gather_SEP 0 1 2. 
  replace_SEP 0
    (field_at Tsh t_struct_SHA256state_st [StructField _data]
         (map Vint (map Int.repr dd') ++
             list_repeat (Z.to_nat (CBLOCKz - 8 - Zlength dd'))
               (Vint Int.zero) ++ ((map Vint hibytes) ++ (map Vint lobytes))) c).
  {
    assert (LENhi: Zlength hibytes = 4) by reflexivity.
    clearbody hibytes. clearbody lobytes.
    Time entailer!. (*8.7*)
  erewrite field_at_Tarray; try reflexivity;
   [ | apply compute_legal_nested_field_spec'; repeat constructor; auto; omega
   | omega].
   rewrite <- app_ass.
   rewrite (split2_array_at _ _ _ 0 56 64) by omega.
   rewrite (split2_array_at _ _ _ 56 60 64) by omega.
   assert (CBZ: CBLOCKz = 64) by reflexivity.
   clear - CBZ H13 H11 H1 H0 H3 H9 LENhi. rewrite CBZ in *.   
   pose proof (Zlength_nonneg dd').
   Time autorewrite with sublist in * |- * . (*7*)
   replace (Zlength dd' + (64 - 8 - Zlength dd')) with 56 by (clear; omega).
   Time autorewrite with sublist. (*2*)
   Time cancel. (*0.2*)
   rewrite array_at_data_at'; auto.
 }
  Time forward. (* p += 4; *) (*5.1*)
    Time entailer!. (*4.6*)
    pose proof CBLOCKz_eq.
    rewrite field_address_offset by auto with field_compatible.
    normalize.
  Time forward. (* p -= SHA_CBLOCK; *) (*5.9*)
  {
    Time entailer!. (*5.9*)
    pose proof CBLOCKz_eq.
    rewrite field_address_offset by auto with field_compatible.
    make_Vptr c_; simpl in *; auto.
  }
  drop_LOCAL 1%nat. (* drop cNl *)
  drop_LOCAL 1%nat. (* drop cNh *)
  match goal with
  | |- semax _ (PROPx nil (LOCALx (_ :: ?L) (SEPx ?S))) _ _ =>
         apply semax_pre0 with (PROPx nil (LOCALx (
           temp _p (field_address t_struct_SHA256state_st [StructField _data] c)
           :: L) (SEPx S)))
  end.
  Focus 1. {
    clearbody hibytes lobytes.
    Time entailer!. (*3.3*)
    rewrite <- H6.
    pose proof CBLOCKz_eq.
    rewrite !field_address_offset by auto with field_compatible.
    make_Vptr (eval_id _c rho).
    simpl.  rewrite Int.sub_add_opp.
    rewrite !Int.add_assoc.
    Time normalize. (*0.4*)
  } Unfocus.
  change (map Vint hibytes) with (map Vint (map Int.repr (intlist_to_Zlist [hi_part bitlen]))).
  change (map Vint lobytes) with (map Vint (map Int.repr (intlist_to_Zlist [lo_part bitlen]))).
  clear lobytes hibytes.
  change (Vint Int.zero) with (Vint (Int.repr 0)).
  rewrite <- !map_list_repeat.
  rewrite <- !map_app.
  rewrite <- intlist_to_Zlist_app.
  simpl ([hi_part bitlen] ++ [lo_part bitlen]).
  set (lastblock := map Int.repr
          (dd' ++ list_repeat (Z.to_nat (CBLOCKz - 8 - Zlength dd')) 0
              ++ intlist_to_Zlist [hi_part bitlen; lo_part bitlen])).
  assert (H99: Zlength lastblock = CBLOCKz)
    by (unfold lastblock; autorewrite with sublist; omega).
  assert (BYTESlastblock: Forall isbyteZ (map Int.unsigned lastblock)). {
    unfold lastblock.
    repeat rewrite map_app.
    repeat rewrite Forall_app.
    repeat split; auto.
    apply Forall_isbyteZ_unsigned_repr; auto.
    rewrite !map_list_repeat.
    apply Forall_list_repeat.
    change (Int.unsigned (Int.repr 0)) with 0; split; omega.
    apply isbyte_intlist_to_Zlist'.
  }
  unfold POSTCONDITION, abbreviate.
  fold (SHA_256 (intlist_to_Zlist hashed ++ dd)).
  pose (lastblock' := Zlist_to_intlist (map Int.unsigned lastblock)).
  eapply semax_pre; [ | simple apply (sha_final_part3 Espec md c shmd hashed' lastblock'); auto].
  * Time entailer!.
    + apply isbyte_intlist_to_Zlist.
    + Time unfold_data_at 1%nat. (*0.62*) 
      unfold lastblock'.
      rewrite Zlist_to_intlist_to_Zlist; auto.
      2:    rewrite Zlength_map, H99; exists LBLOCKz; reflexivity.
      rewrite map_map with (g := Int.repr).
      replace ((fun x : int => Int.repr (Int.unsigned x))) with (@id int).
      Focus 2.
      {
        extensionality i.
        rewrite Int.repr_unsigned.
        reflexivity.
      } Unfocus.
      rewrite map_id.
      Time cancel. (*0.7*)
  * unfold lastblock'.
     erewrite Zlength_Zlist_to_intlist. reflexivity.
     rewrite Zlength_map; assumption.
  *
apply intlist_to_Zlist_inj.
rewrite intlist_to_Zlist_app.
unfold lastblock'.
rewrite Zlist_to_intlist_to_Zlist; auto.
2: rewrite Zlength_map,H99; exists LBLOCKz; reflexivity.
unfold lastblock.
rewrite !map_app.
rewrite map_unsigned_repr_isbyte by auto.
rewrite <- app_ass. rewrite H5.
rewrite !map_list_repeat.
change (Int.unsigned (Int.repr 0)) with 0.
rewrite map_unsigned_repr_isbyte by apply isbyte_intlist_to_Zlist.
unfold generate_and_pad.
rewrite intlist_to_Zlist_app.
rewrite Zlist_to_intlist_to_Zlist; auto.
repeat rewrite app_ass.
f_equal. f_equal. f_equal.
rewrite <- app_ass.
f_equal.
rewrite list_repeat_app.
f_equal.
clear - H5 H2 H1 H0 PAD.
assert (Zlength dd' <= 56) by (change CBLOCKz with 64 in H0; omega).
clear H0.
replace (Zlength (intlist_to_Zlist hashed ++ dd))
  with (4*Zlength hashed' + Zlength dd' - (1+pad)).
Focus 2. {
rewrite Z.mul_comm.
rewrite <-  Zlength_intlist_to_Zlist.
rewrite <- Zlength_app.
rewrite H5.
rewrite <- app_ass.
rewrite Zlength_app.
forget (Zlength (intlist_to_Zlist hashed ++ dd)) as B.
rewrite Zlength_app.
rewrite Zlength_cons, Zlength_nil, Zlength_correct.
rewrite length_list_repeat. rewrite Z2Nat.id by omega. omega.
} Unfocus.
change (Z.of_nat CBLOCK - 8) with 56.
clear H5.
rewrite <- Z2Nat.inj_add by (change CBLOCKz with 64; omega).
f_equal. {
 transitivity (- (4 * Zlength hashed' + (Zlength dd' - (1 + pad) + 9)) mod 64).
 f_equal. f_equal. omega.
 rewrite <- Z.sub_0_l.
 rewrite Zminus_mod.
 rewrite Zplus_mod.
 rewrite Z.mul_comm.
 destruct H2 as [a H2]; rewrite H2.
 rewrite <- Z.mul_assoc.
 change (LBLOCKz * 4)%Z with 64%Z.
 rewrite Zmult_mod.
 assert (64<>0) by (clear; omega).
 rewrite Z.mod_same by auto. rewrite Z.mul_0_r.
 rewrite Z.mod_0_l at 2 by auto.
 rewrite Z.add_0_l. rewrite Z.mod_mod by auto.
 replace (0 mod 64) with (64 mod 64) by reflexivity.
 change CBLOCKz with 64. change LBLOCKz with 16 in H2.
 destruct PAD; subst.
 rewrite <- Zminus_mod.
 rewrite Z.mod_small; try omega. 
 rewrite Zlength_correct in H|-*; omega.
 rewrite Zlength_nil in *.
 rewrite <- Zminus_mod.
 rewrite Z.mod_small; omega.
}
 rewrite Zlength_app, Zlength_intlist_to_Zlist.
 rewrite H7.
 reflexivity.
{
 autorewrite with sublist.
 rewrite Zlength_list_repeat by (apply Z_mod_lt; computable).
 forget ( Zlength hashed * 4 + Zlength dd) as d.
 change (Z.succ 0) with 1.
 change WORD with 4.
 rewrite Z.add_assoc.
 replace (d + 9) with (d + 1 + 8) by omega.
 forget (d+1) as e.
 apply Zmod_divide; try omega.
 clear.
 rewrite Zplus_mod.
 change 64 with (16*4)%Z.
 rewrite Fcore_Zaux.Zmod_mod_mult by omega.
 rewrite <- Z.sub_0_l.
 rewrite Zminus_mod.
 rewrite (Zplus_mod e 8).
 change (0 mod 4) with (4 mod 4).
 change (8 mod 4) with 0.
 rewrite Z.add_0_r.
  rewrite <- Zminus_mod.
  rewrite <- Zplus_mod.
 replace (e + (4 - e mod 4)) with (4 + (e - e mod 4)) by omega.
 rewrite Zplus_mod. rewrite Z.mod_same by omega.
 rewrite Zminus_mod.   rewrite Z.mod_mod by omega.
 rewrite Z.sub_diag. reflexivity.
}
 repeat (apply Forall_app; split; auto).
 apply isbyte_intlist_to_Zlist.
 constructor; auto. split; clear; omega.
 apply Forall_list_repeat. split; clear; omega. 
Time Qed. (*83.4*)

