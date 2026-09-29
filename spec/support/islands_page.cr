# Serves the islands page to a browser that runs `spy` before the page's
# own scripts, and yields the browser and the store the SSE routes read.
def on_islands_page(spy : String = PAGE_SPY, & : Browser, Shomen::Store ->) : Nil
  with_store do |store|
    SSERoutes.store = store
    SSERoutes::TARGET[0] = "count"
    begin
      with_live_server do |origin|
        with_browser do |browser|
          browser.before_load(spy)
          browser.visit("#{origin}#{IslandRoutes::Page.path}")
          yield browser, store
        end
      end
    ensure
      SSERoutes.store = nil
    end
  end
end
