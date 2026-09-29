environment = "dev"
owner       = "platform-team"

# Key pairs must already exist in the target region (one per instance).
instances = {
  bastion = {
    instance_type = "t3.micro"
    volume_type   = "standard"
    volume_size   = 20
    key_name      = "kp-bastion"
  }

  web = {
    instance_type = "t3.small"
    volume_type   = "gp2"
    volume_size   = 30
    key_name      = "kp-web"
  }

  app = {
    instance_type = "m5.large"
    volume_type   = "gp3"
    volume_size   = 40
    iops          = 4000
    throughput    = 250
    key_name      = "kp-app"
  }

  analytics = {
    instance_type = "c5.large"
    volume_type   = "io1"
    volume_size   = 60
    iops          = 3000 # io1 max ratio is 50:1 -> 60 GiB allows up to 3000
    key_name      = "kp-analytics"
  }

  # Stateful database host — the one instance with prevent_destroy (see NOTES.md).
  db-primary = {
    instance_type = "r5.large"
    volume_type   = "io2"
    volume_size   = 100
    iops          = 5000
    key_name      = "kp-db"
    protected     = true
  }
}
