// The name-length island: how many characters the name field has left.
// The server renders the field and a hidden line; this module fills the
// line, shows it, and keeps it current as the name changes.
export default (island) => {
  const input = island.querySelector("input");
  const left = island.querySelector("p");
  const show = () => {
    left.textContent = `${input.maxLength - input.value.length} characters left`;
  };
  input.addEventListener("input", show);
  show();
  left.hidden = false;
};
