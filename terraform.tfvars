vpc_details={
    cidr_block="10.0.0.0/16"
    name="custom_vpc"
}
public_subnet={
    public1 = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
      name="public_subnet_01"
    }
    public2 = {
      cidr_block        = "10.0.3.0/24"
      availability_zone = "us-east-1b"
      name="public_subnet_02"
    }
}
private_subnet={
    private1 = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1a"
      name="private_subnet_01"
    }
    private2 = {
      cidr_block        = "10.0.4.0/24"
      availability_zone = "us-east-1b"
      name="private_subnet_02"
    }
}
rtb_name="public-rtb"
key_details={
    bastion={
        name="Bastion_KP"
    }
    webserver={
        name="WebServer_KP"
    }
}
authorized_ip=["88.106.83.189/32"]
webserver_details={
    ami           = "ami-0889a44b331db0194"
    instance_type = "t2.micro"
    name          = "Web Server"
    user_data     = "WebServerData.txt"
}
autoscaling_details ={
    name="WebServer_ASG"
    desired=2
    min=2
    max=4
    availability_zones=["us-east-1a", "us-east1b"]
}
bastion_details={
    ami="ami-0889a44b331db0194"
    instance_type="t2.micro"
    name="Bastion Server"
}
rds_details={
    engine="mysql"
    identifier="database-1"
    allocated_storage=20
    engine_version="5.7"
    instance_class="db.t2.micro"
    username="admin"
    password="password123"
}
