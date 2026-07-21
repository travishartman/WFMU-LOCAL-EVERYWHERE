# WFMU-LOCAL-EVERYWHERE

Deploy target: Raspberry Pi Zero 2 W, hostname `wfmu`.

## Deploy workflow

Push to this repo from a laptop, then pull on the Pi — either over a direct SSH session or via a [Raspberry Pi Connect](https://connect.raspberrypi.com) remote shell:

```
git clone https://github.com/travishartman/WFMU-LOCAL-EVERYWHERE.git
```

or, once already cloned:

```
git pull
```

No credentials are needed on the Pi side since the repo is public — `clone`/`pull` work over plain HTTPS.
