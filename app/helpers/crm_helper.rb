module CrmHelper
  def rubles(cents)
    number_to_currency(BigDecimal(cents.to_s) / 100, unit: "₽", format: "%n %u", delimiter: " ", separator: ",")
  end

  def crm_time(time)
    time ? time.utc.strftime("%d.%m.%Y %H:%M UTC") : "—"
  end

  def order_status_label(status)
    { "completed" => "Завершён", "cancelled" => "Отменён" }.fetch(status)
  end
end
