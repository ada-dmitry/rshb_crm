require "test_helper"

class CrmNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @buyer = Customer.create!(external_id: "ui-1", name: "Анна", email: "anna@example.com")
    @empty = Customer.create!(external_id: "ui-2", name: "Демо % _")
    @buyer.orders.create!(external_id: "ui-order-1", ordered_at: Time.utc(2026, 10, 13), total_cents: 12345, status: "completed")
    @buyer.orders.create!(external_id: "ui-order-2", ordered_at: Time.utc(2026, 10, 14), total_cents: 99900, status: "cancelled")
    @buyer.consents.create!(channel: "email", granted: false)
  end

  test "all CRM pages require login" do
    [ "/crm", "/crm/customers", "/crm/customers/#{@buyer.id}", "/crm/segments/new_customers" ].each do |path|
      get path
      assert_redirected_to "/session/new"
    end
  end

  test "dashboard shows demo context counts segments and real navigation" do
    sign_in_as users(:one)
    get "/crm"
    assert_response :success
    assert_select "h1", "Кабинет фермера"
    assert_select "[data-demo-banner]", /Синтетические данные/
    assert_select "[data-reference-date]", /2026-10-13/
    assert_select "a[href='/crm/customers']"
    assert_select "a[href='/crm/segments/new_customers']"
    assert_select "[data-customer-count]", "2"
    assert_select "[data-order-count]", "2"
  end

  test "customer search is case insensitive literal and combined with segment filter" do
    sign_in_as users(:one)
    get "/crm/customers", params: { q: "ANNA@EXAMPLE.COM", segment: "new_customers" }
    assert_response :success
    assert_select "[data-customer-id]", count: 1
    assert_select "a[href='/crm/customers/#{@buyer.id}']", "Анна"
    get "/crm/customers", params: { q: "%" }
    assert_select "[data-customer-id]", count: 1
    assert_select "a[href='/crm/customers/#{@empty.id}']", "Демо % _"
    get "/crm/customers", params: { q: "Анна", segment: "no_purchases" }
    assert_select "[data-empty-state]", /Покупатели не найдены/
    get "/crm/customers", params: { q: "' OR 1=1 --" }
    assert_select "[data-customer-id]", count: 0
  end

  test "pagination is stable preserves search and segment and normalizes invalid pages" do
    21.times { |i| Customer.create!(external_id: "page-#{i}", name: "Покупатель #{i}") }
    sign_in_as users(:one)
    query = { q: "Покупатель", segment: "no_purchases" }
    get "/crm/customers", params: query
    assert_select "[data-customer-id]", count: 20
    assert_select "a[rel='next']" do |links|
      uri = URI.parse(links.first["href"])
      assert_equal query.stringify_keys.merge("page" => "2"), Rack::Utils.parse_nested_query(uri.query)
    end
    get "/crm/customers", params: query.merge(page: 2)
    assert_select "[data-customer-id]", count: 1
    get "/crm/customers", params: query.merge(page: "invalid")
    assert_select "[data-customer-id]", count: 20
    get "/crm/customers", params: query.merge(page: 9999)
    assert_select "[data-customer-id]", count: 1
  end

  test "customer detail shows RFM all order statuses and channel permissions including missing consent" do
    sign_in_as users(:one)
    get "/crm/customers/#{@buyer.id}"
    assert_response :success
    assert_select "h1", "Анна"
    assert_select "[data-rfm-frequency]", "1"
    assert_select "[data-rfm-monetary]", /123,45/
    assert_select "[data-order-id]", count: 2
    assert_select "[data-order-status='cancelled']", "Отменён"
    assert_select "[data-consent-channel='email']", /Нет согласия/
    assert_select "[data-consent-channel='sms']", /Согласие не зафиксировано/
    get "/crm/customers/#{@empty.id}"
    assert_select "[data-empty-orders]", /Заказов пока нет/
    assert_select "[data-rfm-recency]", "—"
  end

  test "order history is paginated independently and most recent order is first" do
    21.times do |i|
      @buyer.orders.create!(external_id: "history-#{i}", ordered_at: Time.utc(2026, 9, 1) + i.days, total_cents: 100, status: "completed")
    end
    sign_in_as users(:one)
    get "/crm/customers/#{@buyer.id}"
    assert_select "[data-order-id]", count: 20
    assert_select "[data-order-id]:first-child td:first-child", "ui-order-2"
    get "/crm/customers/#{@buyer.id}", params: { page: 2 }
    assert_select "[data-order-id]", count: 3
  end

  test "segment detail links to its customers and gives proposals but not a fake campaign endpoint" do
    sign_in_as users(:one)
    get "/crm/segments/new_customers"
    assert_response :success
    assert_select "h1", "Одна недавняя покупка"
    assert_select "[data-proposal]", count: 2
    assert_select "[data-segment-size]", "1"
    assert_select "a[href='/crm/customers?segment=new_customers']"
    assert_select "button[disabled]", /Конструктор кампаний/
    get "/crm/segments/sleeping"
    assert_select "[data-empty-state]", /В этом сегменте пока нет покупателей/
  end

  test "unknown customer and segment return 404 and search output is escaped" do
    sign_in_as users(:one)
    [ "/crm/customers/99999999", "/crm/segments/unknown", "/crm/customers?segment=unknown" ].each do |path|
      get path
      assert_response :not_found
    end
    get "/crm/customers", params: { q: "<script>alert(1)</script>" }
    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_select "input[name='q'][value='<script>alert(1)</script>']"
  end

  test "empty CRM shows explicit states and browsing does not mutate business records" do
    sign_in_as users(:one)
    before = snapshot
    [ "/crm", "/crm/customers", "/crm/customers/#{@buyer.id}", "/crm/segments/new_customers" ].each { |path| get path }
    assert_equal before, snapshot
    Consent.delete_all
    Order.delete_all
    Customer.delete_all
    get "/crm"
    assert_select "[data-empty-state]", /База покупателей пока пуста/
    get "/crm/customers"
    assert_select "[data-empty-state]", /Покупатели не найдены/
  end

  private
    def snapshot
      [ Customer, Order, Consent ].map { |model| model.order(:id).map(&:attributes) }
    end
end
