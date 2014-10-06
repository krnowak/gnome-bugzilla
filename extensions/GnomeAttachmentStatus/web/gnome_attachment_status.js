function showOrHideGnomeAttachmentStatus() {
    var div = document.getElementById('attachment_gnome_attachment_status_combo');
    var ispatch = document.getElementById('ispatch');

    if (div === null || ispatch === null) {
	return 1;
    }

    var selects = div.getElementsByTagName('select');

    if (selects.length < 1) {
	return 1;
    }
    selects[0].disabled = !ispatch.checked;

    1;
}

document.addEventListener('DOMContentLoaded', function () {
    ispatch = document.getElementById('ispatch');
    if (ispatch !== null) {
	ispatch.addEventListener('change', showOrHideGnomeAttachmentStatus);
    }
});
