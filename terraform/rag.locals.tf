locals {
  envs_rag = {
    demo = {
      ec2 = {
        instance_type    = "t3.micro"
        key_pair_name    = "Rabindra-keypair-demo"
        allowed_ssh_cidr = "10.0.0.0/8"
        volume_size      = 20
        volume_type      = "gp3"
      }
      qdrant_port_rest = 6333
      qdrant_port_grpc = 6334
    }
  }
  rag_config = local.envs_rag[var.env]
}
