#!/bin/bash

HOSTNAME=$NAME.int.$DOMAIN
HOSTNAME_PUBLIC=$NAME.$DOMAIN

# Ensure hosts are not in FreeIPA yet
ipa host-del $HOSTNAME || true
ipa host-del $HOSTNAME_PUBLIC || true

ipa host-add --password "$FREEIPA_OTP" $HOSTNAME --force
ipa host-add $HOSTNAME_PUBLIC --force
ipa host-add-managedby $HOSTNAME_PUBLIC --hosts $HOSTNAME

ipa hostgroup-add-member $IPA_HOSTGROUP --hosts=$HOSTNAME

ipa service-add puppet/$HOSTNAME_PUBLIC --force
ipa service-add-host puppet/$HOSTNAME_PUBLIC --hosts $HOSTNAME
