import Lake
open Lake DSL

package math_logic_formalization where

@[default_target]
lean_lib rule_based_submission where
  roots := #[`rule_based_submission.formalization.Environment,
             `rule_based_submission.formalization.Strategy,
             `rule_based_submission.formalization.TaskProofs]
