# Ubuntu automatic updates

Managed by `hetzner/ansible/ubuntu-updates.yml`. Applied on `cool` on 2026-10-26.

| Europe/Berlin time | Action |
| --- | --- |
| 01:00 daily | `apt-daily.service` refreshes package lists. |
| 02:00 daily | `apt-daily-upgrade.service` runs unattended upgrades. |
| 03:00 when required | Unattended upgrades schedules reboot if `/var/run/reboot-required` exists after an upgrade. |

Host timezone is `Europe/Berlin`. Both APT timers have no randomized delay and `Persistent=false`. A missed night is skipped rather than caught up during daytime. Daily `APT::Periodic` settings are managed by Ansible; Ubuntu's default allowed origins remain in effect. Automatic reboot proceeds even with an SSH user logged in. No reboot occurs every night by default.

Only third-party APT repository found before applying this policy was Docker's. Ubuntu's default unattended-upgrades configuration does not automatically update packages from that repository. Docker is stopped and slated for removal with Coolify. When adding a third-party APT repository later, decide whether to allow its automatic upgrades and add the specific origin in a managed APT configuration file. K3s is not an APT package in the proposed setup; its upgrade schedule is separate.

The 03:00 reboot time is a target, not a hard maintenance cutoff if package installation takes longer. Ubuntu package updates can also restart affected services during the 02:00 run.

Europe/Berlin skips 02:00 during the spring daylight-saving transition. That one unattended-upgrade run is skipped; the next daily run is the following night. `systemd-analyze calendar` on host confirmed this behavior. The 01:00 package refresh still runs that day.

## Apply again

From repository root on Mac, with Ansible installed (version pinned in `hetzner/ansible/requirements.txt`):

```bash
ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/ubuntu-updates.yml
```

For an isolated install on this Mac, `uv venv temp/ansible-venv` followed by `uv pip install --python temp/ansible-venv/bin/python -r hetzner/ansible/requirements.txt` works. Then call `temp/ansible-venv/bin/ansible-playbook` with the same arguments. `temp/` remains ignored by Git.

Playbook requires root SSH access. It writes only these configuration files, changes host timezone, reloads systemd, and restarts the two timer units when needed:

```text
/etc/systemd/system/apt-daily.timer.d/override.conf
/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf
/etc/apt/apt.conf.d/90selfhosted-unattended-upgrades
```

## Verify

```bash
ssh cool 'timedatectl show -p Timezone; systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager; apt-config dump | grep -E "^Unattended-Upgrade::Automatic-Reboot"'
ssh cool 'systemctl cat apt-daily.timer apt-daily-upgrade.timer'
ssh cool 'journalctl -u apt-daily-upgrade.service --since yesterday --no-pager'
```

The last command shows actual run history after next maintenance night. Do not trigger a live upgrade merely to test scheduling.

## Roll back this policy

This restores Ubuntu's packaged APT timers and disables our automatic reboot setting. It does not revert other migration work:

```bash
ssh cool 'rm -f /etc/systemd/system/apt-daily.timer.d/override.conf /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf /etc/apt/apt.conf.d/90selfhosted-unattended-upgrades; systemctl daemon-reload; systemctl restart apt-daily.timer apt-daily-upgrade.timer; timedatectl set-timezone Etc/UTC'
```

Ubuntu's original `20auto-upgrades` and vendor `50unattended-upgrades` files were not modified.
