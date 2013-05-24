function activateTabByAnchor() {
  var anchor = window.location.hash.substring(1);
  if(anchor) {
    $('.nav-tabs a[href="#' + anchor + '-pane"]').click();
  }
}

function validateQuestionsForm() {
  var form = $(this).parents('form.questions');
  var valid = validateForm(form);

  form.find('button.continue').prop('disabled', !valid);
}

function validateForm(form) {
  return validateTextInputs(form) &&
         validateRadioInputs(form);
}

function validateTextInputs(form) {
  return form.find('input.answer[type="text"]').filter(function() {
    return $(this).val() === '';
  }).size() === 0;
}

function validateRadioInputs(form) {
  return form.find('input.answer[type="radio"]').filter(function() {
    var group = $(this).attr('name');
    return form.find('input.answer[type="radio"][name="' + group + '"]').filter(function() {
      return $(this).prop('checked');
    }).size() === 0;
  }).size() === 0;
}

$(function() {
  activateTabByAnchor();
  $('form.questions input.answer').
    keyup(validateQuestionsForm).
    change(validateQuestionsForm);
});
