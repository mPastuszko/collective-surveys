function activateTabByAnchor() {
  var anchor = window.location.hash.substring(1);
  if(anchor) {
    $('.nav-tabs a[href="#' + anchor + '-pane"]').click();
  }
}

$(function() {
  activateTabByAnchor();
});
