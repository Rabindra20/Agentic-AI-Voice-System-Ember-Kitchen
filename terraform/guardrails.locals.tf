locals {
  envs_guardrails = {
    demo = {
      blocked_input_messaging   = "I'm sorry, I can't help with that topic. Is there anything else I can assist you with regarding your reservation or dining experience at Ember Kitchen?"
      blocked_outputs_messaging = "I'm sorry, I can't provide that information. Is there anything else I can help you with?"
    }
  }
  guardrails_config = local.envs_guardrails[var.env]
}
