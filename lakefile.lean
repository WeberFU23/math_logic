import Lake
open Lake DSL

package math_logic_formalization where
  buildDir := ".lake/build_rl"

lean_lib formalization where
  roots := #[`formalization.Environment,
             `formalization.Rule_based_Strategy,
             `formalization.RL_based_Strategy,
             `formalization.Rule_based_TaskProofs,
             `formalization.RL_based_TaskProofs,
             `formalization.Additional_Proofs]