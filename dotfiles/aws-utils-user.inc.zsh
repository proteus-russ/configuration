# This is an example aws-utils configuration file
# A file like this should be named ~/.aws-utils-user.inc.zsh

# For misc hosts that don't follow the naming convention of "NAME-CONTEXT-01" mapping directly to a LEAPP Profile name
# you can specify specific host mappings like this:
ec2hosts[remote-release-01]="proteus-server-prod";
ec2hosts[redir-dev-01]="proteus-server-prod";
ec2hosts[sca-release-01]="proteus-server-prod";
ec2hosts[ci-release-01]="proteus-server-prod";
ec2hosts[repo-release-01]="proteus-server-prod";
