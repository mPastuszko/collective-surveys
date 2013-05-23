function activateTabByAnchor() {
  var anchor = window.location.hash.substring(1);
  if(anchor) {
    $('.nav-tabs a[href="#' + anchor + '-pane"]').click();
  }
}

function validateQuestionsForm() {
  var form = $(this).parents('form.questions');
  var valid = form.find('input.answer').filter(function() {
    return $(this).val() === '';
  }).size() === 0;

  form.find('button.continue').prop('disabled', !valid);
}

$(function() {
  activateTabByAnchor();
  $('form.questions input.answer').keyup(validateQuestionsForm);
});
