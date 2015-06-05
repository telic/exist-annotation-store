xquery version "3.0";


import module namespace auth = "http://max.terpstra.ca/ns/exist-annotation-store#auth" at '../modules/auth.xqm';
import module namespace common = "http://max.terpstra.ca/ns/exist-annotation-store#common" at '../modules/common.xqm';
import module namespace xqjson="http://xqilla.sourceforge.net/lib/xqjson";

declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare option output:method "text";
declare option output:media-type "application/json";

(: provided by the controller :)
declare variable $annotationId := request:get-attribute('annotationId');
declare variable $baseUrl := request:get-attribute('baseUrl');

(: optional query parameters :)
declare variable $q_limit := request:get-parameter('limit', '50');
declare variable $q_offset := request:get-parameter('offset', '1');
declare variable $q_filters := request:get-parameter-names()[not(. = ('limit', 'offset'))];

auth:get-account-then(function($issuer, $user) {
    let $collection := common:collection('annotations/'||$issuer),

    (: make sure limit and offset are numbers :)
        $limit := if ($q_limit castable as xs:integer) then number($q_limit) else 50,
        $offset := if ($q_offset castable as xs:integer) then number($q_offset) else 0,

    (: reconstruct the URL for paging :)
        $url := concat(
            $baseUrl,
            '/annotations?limit=', $limit,
            string-join(
                $q_filters ! concat(
                    '&amp;',
                    xmldb:encode(.),
                    '=',
                    xmldb:encode(request:get-parameter(., ())),
                    ''
                )
            )
        )
        ,

    (: apply filters first, since they'll probably result in the smallest set :)
        $filtered := for $filter in $q_filters return
            $collection//pair[@name=$filter][@type='string']
                [. = request:get-parameter($filter, ())]
        ,
    (: find the annotations :)
        $anns :=
            if (exists($q_filters)) then
                if (auth:is-admin($issuer, $user)) then
                    $filtered/ancestor::json
                else
                    $filtered/ancestor::json[
                        pair[@name='permissions']/pair[@name='read'][@type='array'][item=$user]
                        or
                        pair[@name='permissions']/pair[@name='read'][@type='null']
                    ]
            else
                if (auth:is-admin($issuer, $user)) then
                    $collection/json
                else 
                    (
                        $collection//pair[@name='read'][@type='array'][item=$user],
                        $collection//pair[@name='read'][@type='null']
                    )
                        [parent::pair/@name = 'permissions' and count(ancestor::*) = 2]
                        /ancestor::json
        ,

        $total := count($anns)

    return concat(

        '{',
        ' "total":'||$total||',',
        ' "offset":'||$offset||',',
        ' "limit":'||$limit||',',
        ' "rows":[',

        string-join(
            for $a in subsequence(
                for $x in $anns order by $x/pair[@name='created'] descending return $x,
                $offset,
                $limit
            ) return xqjson:serialize-json($a),
            ','
        ),

        ' ]',

        if ($total gt ($offset - 1 + $limit)) then
            ', "next":"'||$url||'&amp;offset='||($offset + $limit)||'"'
        else (),
        if ($offset gt 1) then
            ', "previous":"'||$url||'&amp;offset='||max((1, $offset - $limit))||'"'
        else (),

        '}'
    )

})
