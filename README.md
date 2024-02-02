# Need a WebHost - Use NGINX

NGINX (or Nginx) is a Node.js based web server. Use it to proxy for your web apps, provide SSL Termination (Certs), and other yummy functions.

## Setup

```bash
cp sample.env .env

edit .env
```

## Manual Hacking

To issue the Cert then activate it, some hand hacking of `setup_webhost.md` is currently being used.

* CERTBOT_TEST=true

## Referenced

* https://pentacent.medium.com/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71
