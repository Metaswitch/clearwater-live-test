The live tests allow you to test BGCF routing function, although this
relies on specific configuration on your deployment (whereas the other
live tests should all run successfully against any Project Clearwater
deployment, and can take care of the necessary configuration
themselves.)

This document explains how to run these tests against a BGCF, and what
configuration needs to be done in advance.

## Overview ##

The "Off-net" tests (in [offnet.rb](lib/tests/offnet.rb)) do the
following:

* listen on port 5072
* register a subscriber (as normal - i.e. one automatically
  provisioned on Ellis)
* send a request out from that subscriber to a user-provided number
  (given through the OFF_NET_TEL command-line option)
* checks that this request comes back in on port 5072

This allows it to test any BGCF rule that routes back to port 5072 on
your test machine. In other words, to use this test effectively, you
should:

* choose a number (e.g. 2011000001)
* learn the IP address of your test machine (e.g. 10.0.0.1)
* set up your Clearwater deployment's ENUM, BGCF and firewall settings
  so that a call to the 2011000001 will be routed back to
  `sip:10.0.0.1:5072;transport=tcp`
* Run `rake test[<DEPLOYMENT>] TESTS="Off-net*" OFF_NET_TEL=2011000001`
  to run the off-net calling tests against this number

## Example: testing standard BGCF routing ##

* Set the following route in bgcf.json:
```
                {   "name" : "Test 1",
                    "domain" : "otherdomain",
                    "route" : ["sip:10.0.0.1:5072;transport=tcp"]
                }
```
* Set up the following ENUM entry:
        `1.0.0.0.0.0.0.0.0.1.e164.arpa.	3600	IN	NAPTR	1 1 "u" "E2U+sip" "!(^.*$)!sip:\\1@otherdomain!"`
*  Run `rake test[<DEPLOYMENT>] TESTS="Off-net*" OFF_NET_TEL=1000000001`

## Example: testing NP ##

* Set the following route in bgcf.json:
```
                {   "name" : "Test 2",
                    "routing number" : "1234-567-890",
                    "route" : ["sip:10.0.0.1:5072;transport=tcp"]
                }
```
* Set up the following ENUM entry:
        `1.0.0.0.0.0.0.0.0.2.e164.arpa.	3600	IN	NAPTR	1 1 "u" "E2U+pstn:tel" "!(^.*$)!tel:\\1;npdi;rn=1234567890!"`
*  Run `rake test[<DEPLOYMENT>] TESTS="Off-net*" OFF_NET_TEL=2000000001`
