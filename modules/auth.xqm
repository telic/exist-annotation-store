xquery version "3.0";
module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth";

import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at "common.xqm";
import module namespace jwt = "http://max.terpstra.ca/ns/exist-jwt";
import module namespace xqjson = "http://xqilla.sourceforge.net/lib/xqjson";

declare variable $auth:MISSING_JWT := xs:QName('auth:MISSING_JWT'); (: no JWT given :)
declare variable $auth:UNKNOWN_KEY := xs:QName('auth:UNKNOWN_KEY'); (: can't match a key to verify the JWT :)
declare variable $auth:MISSING_USER := xs:QName('auth:MISSING_USER'); (: 'sub' not specified in JWT :)
declare variable $auth:MISSING_ISS := xs:QName('auth:MISSING_ISS'); (: 'iss' not specified in JWT :)
declare variable $auth:INVALID_JWT := xs:QName('auth:INVALID_JWT'); (: opaque JWT error :)
declare variable $auth:UNKNOWN_ISSUER := xs:QName('auth:UNKNOWN_ISSUER'); (: issuer not registered in this store :)
declare variable $auth:INVALID_USER := xs:QName('auth:INVALID_USER'); (: user name must be a string or number :)

declare variable $auth:READ_PERM_REQUIRED := xs:QName('auth:READ_PERM_REQUIRED');
declare variable $auth:UPDATE_PERM_REQUIRED := xs:QName('auth:UPDATE_PERM_REQUIRED');
declare variable $auth:ADMIN_PERM_REQUIRED := xs:QName('auth:ADMIN_PERM_REQUIRED');
declare variable $auth:DELETE_PERM_REQUIRED := xs:QName('auth:DELETE_PERM_REQUIRED');

declare variable $auth:JWT_HEADER as xs:string := string(doc('../store-configuration.xml')//jwt-header);

(: callback for jwt:get-verified-claims :)
declare %private function auth:callback($issuer as xs:string) as xs:string* {
    let $issRecord := common:collection('issuers')/id($issuer)
    return
        if (empty($issuer)) then error($auth:MISSING_ISS, 'the JWT payload must include a "iss" field that matches a known issuer ID in this store')
        else if (empty($issRecord)) then error($auth:UNKNOWN_ISSUER, 'JWT issuer "'||$issuer||'" is not registered in this store')
        else
            for $key in $issRecord/key
            return xqjson:serialize-json($key)
};

(:~
 : Get the user account information from a JWT in the request.
 : 
 : @return a map with 'user' and 'issuer' keys
 : 
 : @error auth:MISSING_JWT
 : @error auth:MISSING_USER
 : @error auth:INVALID_USER
 : @error auth:MISSING_ISS
 : @error auth:UNKNOWN_ISSUER
 : @error auth:UNKNOWN_KEY
 : @error auth:INVALID_JWT
 :)
declare function auth:get-account() {
    let $jwt := (
            request:get-header($auth:JWT_HEADER),
            request:get-parameter($auth:JWT_HEADER, ())
        )[1]
    return if ($jwt) then
        try {
            let $claims := jwt:get-verified-claims($jwt, auth:callback#1, $common:site-id),
                $issuer := $claims('iss'),
                $user := $claims('sub')
            return
                if (empty($issuer)) then error() (: should never get here--would have failed in auth:callback() already :)
                else if (empty($user)) then error(
                    $auth:MISSING_USER,
                    'a user ID must be supplied in the JWT payload using the "sub" field'
                )
                else if (not($user castable as xs:double or $user instance of xs:string)) then
                    error($auth:INVALID_USER, 'user IDs should be either numbers or strings')
                else
                    map {
                        'user' := $user,
                        'issuer' := $issuer
                    }
        }
        (: wrap jwt errors in our own, in case we want to change the implementation :)
        catch jwt:NO_KEY_ERR {
            error(
                $auth:UNKNOWN_KEY,
                $err:description,
                $err:value
            )
        }
        (: note: this should be jwt:*, but eXist barfs on that :)
        catch * {
            error(
                $auth:INVALID_JWT,
                $err:description,
                $err:value
            )
        }
    else error(
        $auth:MISSING_JWT,
        'you must authenticate using a JWT in a "'||$auth:JWT_HEADER||'" header or request parameter'
    )
};

(:~
 : Check if the given user is an admin for the given issuer.
 : 
 : @param $issuer ID of the issuer
 : @param $user ID of the user
 : 
 : @return true if $user is an admin for $issuer
 :)
declare function auth:is-admin($issuer, $user) as xs:boolean {
    common:collection('issuers')/id($issuer)/admin = $user
};

declare %private function auth:may-do($issuer, $user, $ann as element(json), $action) as xs:boolean {
    auth:is-admin($issuer, $user)
    or
    $ann/pair[@name='permissions']/pair[@name=$action][@type='array'][item=$user]
    or
    (
        empty($ann/pair[@name='permissions']/pair[@name=$action][@type='null']) and
        empty($ann/pair[@name='permissions']/pair[@name=$action][@type='array']/item)
    )
};
declare function auth:may-read($issuer, $user, $ann as element(json)) as xs:boolean {
    auth:may-do($issuer, $user, $ann, 'read')
};
declare function auth:may-update($issuer, $user, $ann as element(json)) as xs:boolean {
    auth:may-do($issuer, $user, $ann, 'update')
};
declare function auth:may-delete($issuer, $user, $ann as element(json)) as xs:boolean {
    auth:may-do($issuer, $user, $ann, 'delete')
};
declare function auth:may-admin($issuer, $user, $ann as element(json)) as xs:boolean {
    auth:may-do($issuer, $user, $ann, 'admin')
};

declare function auth:standard-permissions($issuer, $user) as element(pair)+ {
    <pair name="read" type="array"><item type="string">{$user}</item></pair>,
    <pair name="update" type="array"><item type="string">{$user}</item></pair>,
    <pair name="delete" type="array"><item type="string">{$user}</item></pair>,
    <pair name="admin" type="array"><item type="string">{$user}</item></pair>
};

declare function auth:permissions-differ($left, $right) as xs:boolean {
    some $ptype in ('read', 'update', 'delete', 'admin') satisfies
    let $lvalues := distinct-values($left/pair[@name=$ptype]/item),
        $rvalues := distinct-values($right/pair[@name=$ptype]/item)
    return
        (: one side missing :)
        (empty($left/pair[@name=$ptype]) and exists($right/pair[@name=$ptype])) or
        (empty($right/pair[@name=$ptype]) and exists($left/pair[@name=$ptype]))
        or
        (: different types; eg. null vs array :)
        $left/pair[@name=$ptype]/@type != $right/pair[@name=$ptype]/@type
        or
        (: some value in one that isn't in the other :)
        exists(($lvalues, $rvalues)[not(. = ($lvalues[. = $rvalues]))])
};

(:~
 : Fixes minor permissions oddities, and fills in missing permissions
 :)
declare function auth:fix-permissions($ann, $issuer, $user) {
    let $std := auth:standard-permissions($issuer, $user),
        $perms := $ann/pair[@name='permissions']
    return
        if (empty($perms)) then
            update insert <pair name="permissions" type="object">{$std}</pair> into $ann
        else
            for $ptype in ('read', 'update', 'delete', 'admin')
            let $p := $perms/pair[@name=$ptype]
            return (
                (: fill in any missing :)
                if (empty($p)) then
                    update insert $std[@name=$ptype] into $perms
                (: interpret number and string values as user IDs :)
                else if ($p/@type = ('number', 'string')) then (
                    let $newVal := <item type="string">{string($p)}</item>
                    return (
                        update value $p with $newVal,
                        update value $p/@type with 'array'
                    )
                )
                (: interpret false as no-access :)
                else if ($p[@type='boolean'] = 'false') then (
                    update value $p/@type with 'null',
                    update delete $p/node()
                )
                (: interpret true as world-access :)
                else if ($p[@type='boolean'] = 'true') then (
                    update value $p/@type with 'array',
                    update delete $p/node()
                )
                (: objects should have been caught by common:parse-and-check()
                   already, and both "null" and "array" are allowed :)
                else ()
                ,
                (: now clean up each item in the array :)
                for $i in $p/item return
                    if ($i[@type=('object', 'array', 'boolean', 'null')]) then update delete $i
                    else if (not(matches($i, '\S'))) then update delete $i
                    else ()
            )
};

(:~
 : Do initial authentication checks (and send an error response if any errors
 : are encountered), then call the given function if all is well.
 : 
 : @param $fn a callback function to run if authentication succeeds.
 :        The function will recieve two string parameters: the issuer ID
 :        and the user ID.
 : 
 : @return nothing if successful, otherwise a JSON error response
 :)
declare function auth:get-account-then($fn as function(*)) as xs:string? {
    try {
        let $credentials := auth:get-account()
        return $fn($credentials('issuer'), $credentials('user'))
    }
    (: note: this should be auth:*, but eXist barfs on that :)
    catch * {
        common:error-response(
            $err:code, $err:description,
            'modules/auth.xqm', $err:line-number
        )
    }
};
