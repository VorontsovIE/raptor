$(document).ready(function () {
  bsCustomFileInput.init();
  $('#submission-name-button').click(function(e){
    e.preventDefault();
    $.getJSON('/random_submission_name', function(data){
      $('#submission-name-input').val(data['name']);
    });
  })
});