function activateTabByAnchor() {
  var anchor = window.location.hash.substring(1).split('-');
  var tab_name = anchor[0];
  var word_anchor = anchor[1];
  if(tab_name) {
    $('.nav-tabs a[href="#' + tab_name + '-pane"]').click();
    if(word_anchor) {
      $(document.body).scrollTop($(anchor).offset().top);
    }
  }
}

function validateQuestionsForm() {
  var form = $(this).parents('form.questions');
  var valid = validateForm(form);

  form.find('button.continue').prop('disabled', !valid);
  form.find('.fill-before-continue-info').css('visibility', valid ? 'hidden' : 'visible');
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

function tabShown(event) {
  var tab_id = $(event.target).
    attr('href').
    slice(0, -5);
  window.location.hash = tab_id;
}

function putLoaderAfter(element) {
  $(element).after('<img src="/img/ajax_loader_gray_16.gif" class="context-loader">');
}

function putLoaderIn(element) {
  $(element).append('<img src="/img/ajax_loader_gray_16.gif" class="context-loader">');
}

$(function() {
  activateTabByAnchor();
  $('form.questions input.answer').
    keyup(validateQuestionsForm).
    change(validateQuestionsForm);
  $('#designer-tabs > li > a').
    on('shown', tabShown);
});
