module Items
  Shomen::Island.script "name-length", "name_length.js"

  # The list the index shows, and the stream sends again after an append.
  class ListFragment < Shomen::Fragment
    def initialize(@items : Array(Item))
    end

    def content : Nil
      items = @items
      div(id: "item-list") do
        if items.empty?
          p "No items yet"
        else
          ul do
            items.each do |item|
              li do
                a item.tag, href: Items::Show.path(tag: item.tag)
                text " #{item.name}: "
                text(item.borrower.try { |borrower| "lent to #{borrower}" } || "available")
              end
            end
          end
        end
      end
    end
  end

  class IndexView < Shomen::View
    def initialize(@list : ListFragment)
    end

    def to_html : String
      list = @list
      html lang: "en" do
        head do
          title "Equipment"
          shomen_script
        end
        body do
          main do
            h1 "Equipment"
            a "Register an item", href: Items::New.path
            # One holder per page; the stream sends the list after each append.
            div(id: "items-live", "data-shomen-sse": Items::Live.path) do
              embed list
            end
          end
        end
      end
    end
  end

  class NewView < Shomen::View
    def initialize(@tag : String, @name : String, @token : String, @messages : Array(String))
    end

    def to_html : String
      tag = @tag
      name = @name
      token = @token
      messages = @messages
      html lang: "en" do
        head do
          title "Register an item"
          shomen_script
        end
        body do
          main do
            h1 "Register an item"
            unless messages.empty?
              div(role: "alert") do
                messages.each { |message| p message }
              end
            end
            form(action: Items::Create.path, method: "post") do
              csrf_field(token)
              label("Tag", for: "tag")
              input(id: "tag", name: "tag", type: "text", value: tag, maxlength: "20")
              # Without JavaScript the count would never change, so it stays
              # hidden until the island runs.
              div("data-shomen-island": "name-length", id: "name-field") do
                label("Name", for: "name")
                input(id: "name", name: "name", type: "text", value: name, maxlength: "80")
                p "", id: "name-left", "aria-live": "polite", hidden: "hidden"
              end
              button "Register", type: "submit"
            end
            a "Back to the list", href: Items::Index.path
          end
        end
      end
    end
  end

  # The status and the one form that fits it. shomen.js sends the form with
  # Shomen-Target, so a 409 or 422 replaces only this element.
  class LoanFormFragment < Shomen::Fragment
    def initialize(@item : Item, @token : String, @borrower : String, @error : String?)
    end

    def content : Nil
      item = @item
      token = @token
      borrower = @borrower
      error = @error
      div(id: "loan-form") do
        if message = error
          p message, role: "alert"
        end
        if holder = item.borrower
          p "Lent to #{holder}", id: "status"
          form(action: Items::Return.path(tag: item.tag), method: "post", "data-shomen-post": "loan-form") do
            csrf_field(token)
            input(type: "hidden", name: "version", value: item.version.to_s)
            button "Record the return", type: "submit", id: "return-submit"
          end
        else
          p "Available", id: "status"
          form(action: Items::Lend.path(tag: item.tag), method: "post", "data-shomen-post": "loan-form") do
            csrf_field(token)
            input(type: "hidden", name: "version", value: item.version.to_s)
            label("Borrower", for: "borrower")
            input(id: "borrower", name: "borrower", type: "text", value: borrower, maxlength: "80")
            button "Lend", type: "submit", id: "lend-submit"
          end
        end
      end
    end
  end

  class HistoryFragment < Shomen::Fragment
    def initialize(@loans : Array(Loan))
    end

    def content : Nil
      loans = @loans
      div(id: "history") do
        h2 "Loans"
        if loans.empty?
          p "No loans yet"
        else
          ul do
            loans.each do |loan|
              li "#{loan.borrower}, lent #{loan.lent_at}, #{loan.returned_at.try { |at| "returned #{at}" } || "not returned"}"
            end
          end
        end
      end
    end
  end

  class ShowView < Shomen::View
    def initialize(@item : Item, @form : LoanFormFragment, @history : Shomen::Fragment)
    end

    def to_html : String
      item = @item
      form_view = @form
      history = @history
      html lang: "en" do
        head do
          title "Item"
          shomen_script
        end
        body do
          main do
            h1 "#{item.tag} #{item.name}"
            embed form_view
            embed history
            a "Back to the list", href: Items::Index.path
          end
        end
      end
    end
  end
end
