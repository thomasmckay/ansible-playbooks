Convenience alias
```
function fam { sudo docker run -it --rm --volume /home/thomasmckay/code/forklift/user_playbooks/examplecorp/$1.yml:/foreman-ansible-modules/test/test_playbooks/$1.html fam:latest  --extra-vars "foreman_server_url=https://192.168.123.230" /foreman-ansible-modules/test/test_playbooks/$1.html; }

export -f fam

fam products
```
