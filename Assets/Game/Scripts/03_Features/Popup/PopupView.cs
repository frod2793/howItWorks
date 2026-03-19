using UnityEngine;
using TMPro;
using UnityEngine.UI;
using DG.Tweening;
using Cysharp.Threading.Tasks;

#region 뷰 (View)
/// <summary>
/// [설명]: 기존 팝업 기능에 스프라이트 애니메이션과 자막(타이핑 효과) 연동이 추가된 고도화된 뷰 클래스입니다.
/// </summary>
public class PopupView : MonoBehaviour
{
    #region 에디터 설정
    [Header("Basic UI Elements")]
    [SerializeField] private TMP_Text m_messageText;
    [SerializeField] private Button m_confirmButton;
    [SerializeField] private RectTransform m_popupPanel;

    [Header("Extended Content Settings")]
    [SerializeField] private TMP_Text m_subtitleText;
    [SerializeField] private Animator m_contentAnimator;
    [SerializeField] private TypewriterEffect m_subtitleTypewriter;

    #region 에디터 설정 (디버그/테스트)
    [Header("Debug Settings")]
    [SerializeField] private bool m_loopSubtitle;
    [SerializeField] private string m_testKey;
    #endregion
    #endregion

    #region 내부 필드
    private IPopupViewModel m_viewModel;
    private PopupDataProvider m_debugDataProvider;
    private ISoundService m_soundService;
    #endregion

    #region 초기화 및 바인딩 로직
    [VContainer.Inject]
    public void Construct(ISoundService soundService)
    {
        m_soundService = soundService;
    }
    public void Initialize(IPopupViewModel viewModel)
    {
        if (viewModel == null) return;
        m_viewModel = viewModel;

        // 팝업 시에는 배경의 타이핑 사운드 등을 중지
        m_soundService?.StopLoopSFX();

        // 기본 텍스트 설정
        if (m_messageText != null) m_messageText.text = m_viewModel.Message;
        
        // 자막 텍스트 초기화
        if (m_subtitleText != null) m_subtitleText.text = "";

        // 버튼 바인딩
        if (m_confirmButton != null)
        {
            m_confirmButton.onClick.RemoveAllListeners();
            m_confirmButton.onClick.AddListener(CloseWithAnimation);
        }

        // 전체 팝업 연출 시작
        StartShowSequence().Forget();
    }

    /// <summary>
    /// [설명]: 에디터 테스트를 위해 데이터 제공자만 등록해둡니다 (인스펙터 버튼용).
    /// </summary>
    public void SetupTestDebug(PopupDataProvider dataProvider)
    {
        m_debugDataProvider = dataProvider;
    }

    /// <summary>
    /// [설명]: 인스펙터 버튼을 통해 호출되는 테스트 메서드입니다.
    /// </summary>
    [ContextMenu("Test Current Key")]
    public void TestFromInspector()
    {
        if (m_debugDataProvider == null || string.IsNullOrEmpty(m_testKey))
        {
            Debug.LogWarning("[PopupView] 테스트 데이터 제공자가 없거나 테스트 키가 비어있습니다.");
            return;
        }

        var data = m_debugDataProvider.GetPopupData(m_testKey);
        var testVM = new PopupViewModel(data.Message, data.Subtitle, data.AnimationKey);
        Initialize(testVM);
    }
    #endregion

    #region 애니메이션 및 연출 로직
    private async UniTaskVoid StartShowSequence()
    {
        // 1. 팝업 패널 스케일 업 (기본 애니메이션)
        await ShowPanelAnimation();

        // 2. 스프라이트 애니메이션 실행 (애니메이션 키가 있는 경우)
        if (m_contentAnimator != null && !string.IsNullOrEmpty(m_viewModel.AnimationKey))
        {
            ResetAllAnimatorBools();
            m_contentAnimator.SetBool(m_viewModel.AnimationKey, true);
        }

        // 3. 자막 한 줄씩 순차 타이핑 시작 (자막 내용이 있는 경우)
        if (m_subtitleTypewriter != null && !string.IsNullOrEmpty(m_viewModel.Subtitle))
        {
            var lines = m_viewModel.Subtitle.Split('\n');
            
            do
            {
                foreach (var line in lines)
                {
                    if (string.IsNullOrWhiteSpace(line)) continue;
                    
                    await m_subtitleTypewriter.Play(m_subtitleText, line.Trim());
                    
                    // 줄 사이 대기 시간 (사용자 경험을 위해 1초 정도 대기)
                    await UniTask.Delay(System.TimeSpan.FromSeconds(1.0f), cancellationToken: this.GetCancellationTokenOnDestroy());
                }

                // 루프 사이 짧은 대기 (다시 처음으로 돌아가기 전)
                if (m_loopSubtitle)
                {
                    await UniTask.Delay(System.TimeSpan.FromSeconds(0.5f), cancellationToken: this.GetCancellationTokenOnDestroy());
                }

            } while (m_loopSubtitle);
        }
    }

    private async UniTask ShowPanelAnimation()
    {
        gameObject.SetActive(true);
        if (m_popupPanel != null)
        {
            m_popupPanel.localScale = Vector3.zero;
            await m_popupPanel.DOScale(Vector3.one, 0.4f).SetEase(Ease.OutBack).ToUniTask();
        }
    }

    private void CloseWithAnimation()
    {
        // 타이핑 중이면 즉시 중단
        if (m_subtitleTypewriter != null) m_subtitleTypewriter.Stop();

        // 애니메이터 상태 초기화
        ResetAllAnimatorBools();

        if (m_popupPanel != null)
        {
            m_popupPanel.DOScale(Vector3.zero, 0.2f).SetEase(Ease.InBack).OnComplete(() =>
            {
                gameObject.SetActive(false);
                m_viewModel.Close();
            });
        }
        else
        {
            gameObject.SetActive(false);
            m_viewModel.Close();
        }
    }

    /// <summary>
    /// [설명]: 애니메이터 내의 모든 Bool 파라미터를 false로 초기화합니다.
    /// </summary>
    private void ResetAllAnimatorBools()
    {
        if (m_contentAnimator == null) return;

        foreach (var param in m_contentAnimator.parameters)
        {
            if (param.type == AnimatorControllerParameterType.Bool)
            {
                m_contentAnimator.SetBool(param.name, false);
            }
        }
    }

    private void PlayTypingSound()
    {
        // 개별 재생 대신 루핑 사운드를 사용하므로 이 메서드는 비워둡니다.
    }

#endregion
}
#endregion
