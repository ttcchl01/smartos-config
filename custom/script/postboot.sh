#!/usr/bin/bash

## Load configuration information from USBKey
. /lib/svc/share/smf_include.sh
. /lib/sdc/config.sh

load_sdc_sysinfo
load_sdc_config

## Set the PATH environment because of other commands in /usr
PATH=/usr/bin:/usr/sbin:${PATH}

## Symlink some config files to the root user
for fullpath in /opt/custom/profile/*; do
	filename=${fullpath##*/}
	ln -nsf "${fullpath}" "/root/.${filename}"
done

## Setup fully qualified domain name
hostname=${CONFIG_admin_nic//:/-}
if [[ ${CONFIG_dns_domain} ]]; then
	cp /etc/inet/hosts /tmp
	sed "s_${hostname}\$_${hostname} ${hostname}.${CONFIG_dns_domain}_g" /tmp/hosts \
		> /etc/inet/hosts
fi

## Sendmail configuration for SmartHost setup
if [[ ${CONFIG_mail_smarthost} ]]; then
	cp /etc/mail/{submit.cf,sendmail.cf} /tmp/
	sed "s:^DS$:DS[${CONFIG_mail_smarthost}]:g" /tmp/submit.cf > /etc/mail/submit.cf
	sed "s:^DS$:DS[${CONFIG_mail_smarthost}]:g" /tmp/sendmail.cf > /etc/mail/sendmail.cf
	svcadm refresh sendmail-client
	svcadm refresh sendmail
fi
if [[ ${CONFIG_mail_auth_user} ]]; then
	echo 'AuthInfo:'${CONFIG_mail_smarthost}' "U:'${CONFIG_mail_auth_user}'" "I:'${CONFIG_mail_auth_user}'" "P:'${CONFIG_mail_auth_pass}'"' \
		> /etc/mail/default-auth-info
	echo -e 'Kauthinfo hash /etc/mail/default-auth-info
O AuthMechanisms=EXTERNAL GSSAPI DIGEST-MD5 CRAM-MD5 LOGIN PLAIN
Sauthinfo
R$*\t\t\t$: <$(authinfo AuthInfo:$&{server_name} $: ? $)>
R<?>\t\t$: <$(authinfo AuthInfo:$&{server_addr} $: ? $)>
R<?>\t\t$: <$(authinfo AuthInfo: $: ? $)>
R<?>\t\t$@ no               no authinfo available
R<$*>\t\t$# $1' \
	| tee -a /etc/mail/sendmail.cf >> /etc/mail/submit.cf
	makemap hash /etc/mail/default-auth-info < /etc/mail/default-auth-info
	chgrp smmsp /etc/mail/default-auth-info.db
fi

## Redirect all root emails to admin address
if [[ ${CONFIG_mail_adminaddr} ]]; then
	echo "root: ${CONFIG_mail_adminaddr}" >> /etc/mail/aliases
	newaliases
fi

## Setup crontabs only for root user
cat /opt/custom/crontab/* | crontab

## Special configuration by hostname
if [[ -d "/opt/custom/script/${hostname}" ]]; then
	for script in "/opt/custom/script/${hostname}/"*.sh; do
		./${script} ${hostname}
	done
fi

## Delete all temp files created
rm /tmp/{hosts,submit.cf,sendmail.cf}

exit $SMF_EXIT_OK