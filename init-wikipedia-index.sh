#!/bin/bash

##
# based on https://www.elastic.co/blog/loading-wikipedia
##

# bring up elastic search
docker-compose up -d

# set some variables
es=localhost:9200

# set up simplewikipedia
index=simplewiki
site=simple.wikipedia.org

# set up english wiki quote
# index=enwikiquote
# site=en.wikiquote.org

# set up english wikipedia
index=enwiki
site=en.wikipedia.org

dump=$index-20171009-cirrussearch-content.json.gz

# download index (https://dumps.wikimedia.org/other/cirrussearch/)
curl -s 'https://dumps.wikimedia.org/other/cirrussearch/current/'$dump > $dump

# use dump from the creation of this script
# curl -s 'https://dumps.wikimedia.org/other/cirrussearch/20171009/'$dump > $dump

# init index
curl -XDELETE $es/$index?pretty

# dump current settings
curl -s 'https://'$site'/w/api.php?action=cirrus-settings-dump&format=json&formatversion=2' > settings.json

# dump current mappings
curl -s 'https://'$site'/w/api.php?action=cirrus-mapping-dump&format=json&formatversion=2' > mappings.json

# create index with settings (reformat cirrus dump to elasticsearch v5.5.2 settings)
cat settings.json |
  jq '{
    settings: {
      analysis: .content.page.index.analysis,
      index: {
        similarity: .content.page.index.similarity,
      }
    },
    number_of_shards: 1,
    number_of_replicas: 0
  }' |
  curl -XPUT $es/$index?pretty -d @-

# add mappings to index (reformat cirrus dump to elasticsearch v5.5.2 mappings)
cat mappings.json |
  sed 's/"index_analyzer"/"analyzer"/' |
  sed 's/"position_offset_gap"/"position_increment_gap"/' |
  jq '.content.page' |
  curl -XPUT $es/$index/_mapping/page?pretty -d @-

# extract the dump and prepare data chunks
mkdir -p chunks && cd chunks
gzcat $dump | split -a 10 -l 500 - $index

# import the data
for file in *; do
  echo -n "${file}:  "
  took=$(curl -H 'Content-Type: application/json' -s -XPOST $es/$index/_bulk?pretty --data-binary @$file |
    grep took | cut -d':' -f 2 | cut -d',' -f 1)
  printf '%7s\n' $took
  [ "x$took" = "x" ] || rm $file
done

# speed up, enter in a different terminal
# curl -XPUT "$es/$index/_settings?pretty" -d '{
#     "index" : {
#         "refresh_interval" : -1
#     }
# }'

# monitor progress, enter in a different terminal
# date; curl $es/$index/_refresh?pretty; curl $es/$index/_count?pretty

# is the index fixed? optimize it!
# _optimize?max_num_segments=1
