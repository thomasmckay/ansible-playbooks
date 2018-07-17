Convenience alias
```
function fam { sudo docker run -it --rm --volume /home/thomasmckay/code/forklift/user_playbooks/examplecorp:/foreman-ansible-modules/examplecorp fam:latest  --extra-vars "foreman_server_url=https://192.168.123.230" /foreman-ansible-modules/examplecorp$1.yml; }

export -f fam

fam products
```
