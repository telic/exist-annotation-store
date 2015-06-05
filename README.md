What is this?
=============

This is an [eXist-db application](http://exist-db.org) for storing/managing annotations for [OpenAnnotation's Annotator](http://annotatorjs.org/).

Like the [Python reference implementation](https://github.com/openannotation/annotator-store), it supports multiple sites (aka "consumers"), handles authorization with JWT, supports search and permissions, has an extensible data model, etc, etc.

What's wrong with it?
=====================

It's currently functional (and being used!), but still has a few major issues:
 [ ] there is no interface/API for managing issuers. See below for instructions on setting one up manually.
 [ ] it uses standard JWT fields ('iss', 'sub', 'exp'..) instead of the random ones the Auth plugin expects, so your JWTs will need to have a bunch of duplicated claims to appease both sides
 [ ] the permissions model follows [what's vaguely documented](http://docs.annotatorjs.org/en/v1.2.x/plugins/permissions.html), which doesn't seem to match up with what the standard Permissions plugin actually does
 [ ] search is pretty basic; only exact matches are supported

Also, CORS needs to be configured manually at the servlet level.

How do I use it?
================

Building/installing
-------------------

There's no compiling necessary; just Zip up the entire thing, call it a XAR, and upload it to your database using the package manager.

This package is dependant on another I wrote [for handling JWTs](https://github.com/telic/exist-jwt), as well as [xqjson](https://github.com/joewiz/xqjson). It's been tested on eXist-2.2.

There is no HTML front-end; use the JSON API and/or eXist's management tools to fiddle with it once it's installed.

Adding Issuers (aka "consumers")
--------------------------------

Every site that uses the store has a record in the 'issuers' collection, and its own data folder in the 'annotations' collection, both named after the issuer ID (aka "consumerKey").  The record in 'issuers' should look something like this:

    <issuer xml:id="de81792f-c10f-4d25-a906-5d27992f64d5">
        <name>Friendly Neighbourhood Annotator</name>
        <key type="object">
            <pair name="kid" type="string">my-key</pair>
            <pair name="alg" type="string">HS512</pair>
            <pair name="k" type="string">secretsecret</pair>
            <pair name="kty" type="string">oct</pair>
            <pair name="use" type="string">sig</pair>
        </key>
        <admin>George</admin>
    </issuer>

Use the ID for the filename (eg. "issuers/de81792f-c10f-4d25-a906-5d27992f64d5.xml").

You can have as many keys and admins as you like, and order doesn't matter.

Each key is a JWK, represented using xqjson's markup conventions but with a root element named 'key' instead of 'json'.  Only keys listed in this record may be used to sign JWTs from this issuer.

Admins are given full create/update/read/delete privileges over all annotations in the issuer's store.
