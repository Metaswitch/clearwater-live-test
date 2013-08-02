Clearwater Live Test Framework
==============================

This framework allows scripted testing of a Clearwater deployment to be used as a system-wide test of a fix/feature.

Project Clearwater is an open-source IMS core, developed by [Metaswitch Networks](http://www.metaswitch.com) and released under the [GNU GPLv3](http://www.projectclearwater.org/download/license/). You can find more information about it on [our website](http://www.projectclearwater.org/) or [our wiki](https://github.com/Metaswitch/clearwater-docs/wiki).

Pre-Requisites
--------------

The test framework requires Ruby 1.9.3 and bundler to be installed.

    sudo apt-get install build-essential git --yes
    curl -L https://get.rvm.io | bash -s stable
    source ~/.rvm/scripts/rvm
    rvm autolibs enable
    rvm install 1.9.3
    rvm use 1.9.3

Installation
------------

To install the framework, clone the repository:

    git clone git@github.com:Metaswitch/clearwater-live-test.git

Then type `bundle install` inside the newly-created `clearwater-live-test` folder to install the required gems.

Running The Tests
-----------------

To run the tests against a deployment, use:

    rake test[<deployment_name>] SIGNUP_CODE=<code>

where `<code>` is the signup code you supplied when configuring Ellis (see /etc/clearwater/config on the Ellis server).

There are various modifiers you can use to determine which subset of tests you wish to run, to use these modifiers, add them to the end of the `rake` command:

 - `TESTS="<glob>"` - to only run tests whos name matches the given glob.
 - `PSTN=true` - to run the PSTN-specific tests (your deployment must have PSTN numbers allocated).
 - `LIVENUMBER=<number>` - to allow running of tests that dial out to real devices (your deployment must have an IBCF node and a working PSTN) the live number given may be dialled as part of running the test and the test will expect it to be answered (so make it a real one!).
 - `REPEATS=<number>` - to allow the suite of tests to be run multiple times.
 - `TRANSPORT=<transports>` - Comma-separated transports to test with.  Allowed tranports are `TCP` and `UDP`.  If not specified, all tests will be run twice, for each transport type.
 - `PROXY=<host>` - to force the tests to run against a particular Bono instance.
 - `ELLIS=<host>` - to override the default FQDN for Ellis.  Useful when running against an AIO node.
 - `HOSTNAME=<host>` - publicly accessible hostname of the machine running the tests, used for the dummy AS.
 - `EXPIRES=<number>` - maximum Expires header expected from Sprout, used for the dummy AS.

For example, to run all the call barring tests (including the international number barring tests) on the test deployment, run:

    rake test[test.cw-ngv.com] TESTS="Call Barring*" PSTN=true

Framework Structure
---------------

Tests in the framework are defined as a combination of a collection of endpoints and
a list of actions for those endpoints to perform.  These actions are converted through the magic of [erubis](http://www.kuwata-lab.com/erubis/) into a SIPp script that is then run.

The output of the SIPp script generation and the record of the messages sent and errors reported by SIPp during the run are saved off in the event of a failure and are very useful for tracking down issues/bugs in the scripts.

The test framework is very punctilious about cleaning up after itself, so there should be no issue with running the tests in any order or running the framework multiple times on one deployment (even at the same time!).

Writing A New Test
------------------

The test definitions are found in `lib/tests/*.rb` and should be pretty self-explanitory.  A basic test structure is as follows:

    TestDefinition.new("Test Description") do |t|
      caller = t.add_sip_endpoint
      callee = t.add_sip_endpoint
      t.set_scenario(
        [
          caller.send("NOTIFY", target: callee),
          callee.recv("NOTIFY"),
          callee.send("200", target: caller),
          caller.recv("200"),
        ]
      )
    end

This (non-functional) example would create two numbers in ellis/homestead then send a NOTIFY transaction between them before destroying the numbers.

There are different types of test that can be defined, based on the requirements on the system under test or on the command line options given at run time:

 - `TestDefinition`: Generic test, only uses Clearwater-registered endpoints.
 - `PSTNTestDefiniton`: PSTN test, requires that `PSTN=true` be passed to rake or the test will be skipped.
 - `LiveTestDefiniton`: Live call test, requires that a live number is given to rake as `LIVENUMBER=...`.
 - `SkippedTestDefinition`: Used to mark out currently broken tests, tests should not be left in this state for longer than necessary.

The templates for messages that sent are specified in the scenario list can be found in the `templates` folder named according to the message they contain.  There are two generic receive templates there too.

Creating Endpoints
------------------

As you saw above, a test can create an endpoint in ellis with `test.add_sip_endpoint`.  It may need an endpoint that is not a Clearwater number (for example for off-net calling), in which case `add_fake_endpoint(<DN>, <domain>)` may be used instead.

To create a PSTN number use `test.add_pstn_endpoint`.  These numbers can make calls out to the PSTN and should be used for live calling/international number dialing tests.  When using these numbers, mark the test as a `PSTNTestDefinition` to ensure it is skipped if PSTN numbers are not available on the system under test.

To create a new public identity for a line, use the `test.add_public_identity` function.  The returned endpoint will share a private ID with the passed in one but will have its own public identity.

When using Clearwater endpoints, a common thing to need to do is to (un)register the endpoint and so `ep.register` and `ep.unregister` have been supplied that return the scenario entries needed to do this (see _Basic Call - Mainline_ for an example of how this is used).

Modifying Simservs
------------------

To change a simservs document for a Clearwater endpoint, use `ep.set_simservs` which takes a hash of options for the document.  See `templates/simsers.xml.erb` for how the options are used and see `SIPpEndpoint::default_simservs` for the options that will be used if not specified in your call to `set_simservs`.

Modifying iFCs
------------------

To change the iFC document for a Clearwater endpoint, use `ep.set_ifcs` which takes a hash of options for the document.  See `templates/ifcs.xml.erb` for how the options are used and see `SIPpEndpoint::default_ifcs` for the options that will be used if not specified in your call to `set_ifcs`.

Sending Messages
----------------

To send a SIP message, use the `ep.send(<template>, target: <endpoint>, ...)` command passing the name of the template to use, a target and any other parameters you like.  These parameters will be made available as functions in the template.  If the parameter is optional, its presence should be tested for with:

    <% if defined? <function> %>

Receiving Messages
------------------

To receive a SIP message, simple add `ep.recv(<message>)` to the scenario.

Pausing
-------

To add a pause in the script (for example to mimic the call progress), use the following incantation (which may also be used for other, non-endpoint-specific actions). 
It is necessary to specify an endpoint so it is clear which sipp script to place the
pause into (in the case of multiple endpoints)

    SIPpPhase.new("pause", sip_caller, timeout: <ms>)

Acknowledgements
----------------
The Clearwater Live Test Framework depends on the following files from the [sipp project](http://sipp.sourceforge.net/).  These are distributed under the [GPL](http://sipp.sourceforge.net/doc/license.html).

*   g711a.cap - pcap file for test announcement
*   sipp - precompiled binary from git commit 3268f48, with RTP/pcap relay enabled
