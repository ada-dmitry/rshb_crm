class CampaignsController < CrmController
  skip_before_action :load_rfm
  around_action :use_utc_zone
  before_action :campaign_context
  before_action :set_campaign, only: %i[ show edit update preview ]

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
    return head :conflict unless @campaign.draft?
    if @campaign.update(campaign_params)
      redirect_to campaign_path(@campaign), notice: "Черновик обновлён. Сообщения не отправлены."
    else
      render :edit, status: :unprocessable_content
    end
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
      @preview = Campaigns::Preview.call(campaign: @campaign)
      @reference_date = @campaign.reference_date
      @window_days = @campaign.window_days
      @pagination_params = {}
      prepare_pagination(@preview.candidate_count)
      @entries = @preview.entries.slice((@page - 1) * 20, 20) || []
    end

    def campaign_params
      params.require(:campaign).permit(:name, :segment, :offer, :body, :channel, :scheduled_at, :reference_date, :window_days)
    end
end
