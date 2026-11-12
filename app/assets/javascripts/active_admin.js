const initializeActiveAdminSelect2 = () => {
  if (!window.jQuery?.fn.select2) {
    throw new Error("ActiveAdmin Select2 requires jQuery and the Select2 plugin");
  }

  window.jQuery("select")
    .not(".select2-hidden-accessible")
    .select2({ width: "100%" });
};

document.addEventListener("DOMContentLoaded", initializeActiveAdminSelect2);
document.addEventListener("turbo:load", initializeActiveAdminSelect2);
