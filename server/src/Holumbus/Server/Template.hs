module Holumbus.Server.Template (
  index 
) where
--import qualified Data.Text      as T
import qualified Data.Text.Lazy as LT

import           Text.Hamlet
import           Text.Julius 
import           Text.Blaze.Html.Renderer.Text (renderHtml)

-- | main page
index :: LT.Text
index = 
  -- generate html with hamlet 
  (renderHtml . defaultLayout $ [xshamlet|
<h1>Holumbus Server
<hr>
<form>
  <div .input-append>
    <input .span6 type=text #txt-search > 
    <button .btn .btn-primary type=button #btn-search>Search
<div  #result>
<hr>
<form>
  <textarea .span6 name=document #txt-document style=height:100px>
    {"desc":{"title":"empty document"},"uri":"id::1","words":{"defaultContext":{"word":[]}}}
  <button .btn .btn-primary #btn-add>
    Add Document
|]) `LT.append` 
  -- generate javascript
  renderJavascriptUrl (\_ _ -> "") [julius|
<script>
  $(document).ready(function() {

    /* add doc button handler */
    $("#btn-add").click(function(ev){
      ev.preventDefault();
      var json = $("#txt-document").val();
      $.post("/document/add", json);
    });



    /* search button handler */
    $("#btn-search").click(function(ev){
      ev.preventDefault();
      var query = $("#txt-search").val();
      $.get("/search/" + query, function(data) {
        if (data.code === 0)
        {
          var docs = data.msg;          
          var res = '<table class="table table-bordered">';
          $(docs).each(function(i,e) {
             res += "<tr><td>" + e.uri + "</td><td>";
             var desc = e.desc
             for (var key in desc){
               res += "<p>" + key + ":" + desc[key] + "</p>";
             }
             res += "</td></tr>";
          });         
          res += "</table>";
          $("#result").html(res);
        }
        else 
        {
          alert("search failed...");
        }
      });
    });
  });
</script>
|]


-- | default layout
--defaultLayout :: forall a.
--                 Text.Blaze.ToMarkup a =>
--                 a -> Text.Blaze.Internal.MarkupM ()
defaultLayout content = [xshamlet|
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Holumbus Server
    <script src="//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.2/js/bootstrap.min.js" type="text/javascript">
    <script src="http://code.jquery.com/jquery-1.10.0.min.js">
    <link href="//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.2/css/bootstrap-combined.min.css" rel="stylesheet">
  <body>
    <div .container>
      #{content}
|]


