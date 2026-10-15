class CampaignsController < CrmController
  skip_before_action :load_rfm
  around_action :use_utc_zone
  before_action :campaign_context
  before_action :set_campaign, only: %i[ show edit update preview confirm launch ]
  rescue_from ActiveRecord::StaleObjectError, with: :stale_campaign

  def index
    @pagination_params = {}
    @campaigns = paginate(Campaign.order(id: :desc))
  end

  def new
    segment = Campaign::SEGMENTS.include?(params[:segment]) ? params[:segment] : "active"
    offer = Campaign::OFFERS.include?(params[:offer]) ? params[:offer] : @segment_definitions.fetch(segment).fetch("recommendations").first
    @campaign = Campaign.new(user: Current.user, name: @segment_definitions.fetch(segment).fetch("label"), segment: segment, offer: offer, channel: "email", scheduled_at: 1.hour.from_now.change(sec: 0))
  end

  def create
    @campaign = Current.user.campaigns.new(campaign_params)
    if @campaign.save
      redirect_to campaign_path(@campaign), notice: "Черновик сохранён. Сообщения не отправлены."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    load_preview
  end

  def preview
    load_preview
    render :show
  end

  def edit
    head :conflict unless @campaign.draft?
  end

  def update
    @campaign.with_lock do
      return head :conflict unless @campaign.draft?
      if @campaign.update(campaign_params)
        redirect_to campaign_path(@campaign), notice: "Черновик обновлён. Подтверждение сброшено. Сообщения не отправлены."
      else
        render :edit, status: :unprocessable_content
      end
    end
  end

  def confirm
    version = params[:version].to_s
    return stale_campaign unless /\A\d+\z/.match?(version)
    @campaign.confirm!(user: Current.user, version: version.to_i)
    redirect_to campaign_path(@campaign), notice: "Текущая версия черновика подтверждена. Сообщения не отправлены."
  rescue Campaigns::Launch::NotReady => error
    launch_rejected(error)
  end

  def launch
    Campaigns::Launch.call(campaign: @campaign)
    redirect_to campaign_path(@campaign), notice: "Локальная симуляция завершена. Реальные сообщения не отправлялись."
  rescue Campaigns::Launch::NotReady => error
    launch_rejected(error)
  end

  private
    def use_utc_zone(&action)
      Time.use_zone("UTC", &action)
    end

    def campaign_context
      @segment_definitions = Segmentation::Rfm::RULES.fetch("segments")
      @offer_definitions = Segmentation::Rfm::RULES.fetch("recommendations")
    end

    def set_campaign
      @campaign = Campaign.find(params[:id])
    end

    def load_preview
      @preview = if @campaign.draft?
        Campaigns::Preview.call(campaign: @campaign)
      else
        Campaigns::Preview::Result.new(entries: @campaign.campaign_recipients.order(:customer_id).to_a, evaluated_at: @campaign.launched_at, generated_at: @campaign.launched_at)
      end
      @reference_date = @campaign.reference_date
      @window_days = @campaign.window_days
      @pagination_params = {}
      prepare_pagination(@preview.candidate_count)
      @entries = @preview.entries.slice((@page - 1) * 20, 20) || []
    end

    def campaign_params
      permitted = params.require(:campaign).permit(:name, :segment, :offer, :body, :channel, :scheduled_at, :reference_date, :window_days)
      permitted[:lock_version] = params[:campaign][:lock_version] if action_name == "update" && params[:campaign].key?(:lock_version)
      permitted
    end

    def stale_campaign
      @campaign.reload
      flash.now[:alert] = "Черновик изменился. Проверьте текущую версию и подтвердите её заново."
      load_preview
      render :show, status: :conflict
    end

    def launch_rejected(error)
      @campaign.reload
      flash.now[:alert] = error.message
      load_preview
      render :show, status: :unprocessable_content
    end
end
