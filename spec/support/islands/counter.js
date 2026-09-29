// A counter kept in the browser. The server renders the count and a hidden
// button; this module shows the button and listens on it alone.
export default (island) => {
  const value = island.querySelector("p");
  const button = island.querySelector("button");
  let count = Number(value.textContent);
  button.addEventListener("click", () => {
    count += 1;
    value.textContent = String(count);
  });
  button.hidden = false;
};
