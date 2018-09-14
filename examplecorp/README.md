Convenience alias
```
function fam { sudo docker run -it --rm --volume /home/thomasmckay/code/forklift/user_playbooks/examplecorp:/foreman-ansible-modules/examplecorp fam:latest  --extra-vars "foreman_server_url=https://192.168.123.230" /foreman-ansible-modules/examplecorp$1.yml; }

export -f fam

fam products
```

[HELLO](https://static-cdn.jtvnw.net/jtv_user_pictures/26a47954-af51-4237-b969-4a8406973c1e-profile_image-300x300.jpg)
