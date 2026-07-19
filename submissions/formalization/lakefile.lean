import Lake
open Lake DSL

package math_logic_formalization where
  buildDir := ".lake/build_rl"

lean_lib formalization where
  roots := #[`Environment,
             `Rule_based_Strategy,
             `Rule_based_TaskProofs,
             `Additional_Proofs]
