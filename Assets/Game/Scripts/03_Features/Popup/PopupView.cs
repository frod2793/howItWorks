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
    [Header("기본 UI 요소")]
    [SerializeField] private TMP_Text m_messageText;
    [SerializeField] private Button m_confirmButton;
    [SerializeField] private RectTransform m_popupPanel;

    [Header("확장 콘텐츠 설정")]
    [SerializeField] private TMP_Text m_subtitleText;
    [SerializeField] private Animator m_contentAnimator;
    [SerializeField] private TypewriterEffect m_subtitleTypewriter;

    #region 에디터 설정 (디버그/테스트)
    [Header("디버그 설정")]
    [SerializeField] private bool m_loopSubtitle;
    [SerializeField] private string m_testKey;
    #endregion
    #endregion

    #region 내부 필드
    private IPopupViewModel m_viewModel;
    private PopupDataProvider m_debugDataProvider;
    #endregion

    #region 초기화 및 바인딩 로직
    public void Initialize(IPopupViewModel viewModel)
    {
        if (viewModel == null)
        {
            return;
        }
        m_viewModel = viewModel;

        if (m_messageText != null)
        {
            m_messageText.text = m_viewModel.Message;
        }
        
        if (m_subtitleText != null)
        {
            m_subtitleText.text = "";
        }

        if (m_confirmButton != null)
        {
            m_confirmButton.onClick.RemoveAllListeners();
            m_confirmButton.onClick.AddListener(func_CloseWithAnimation);
        }

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
    public void func_TestFromInspector()
    {
        if (m_debugDataProvider == null || string.IsNullOrEmpty(m_testKey))
        {
            Debug.LogWarning("[PopupView] 테스트 설정 미비");
            return;
        }

        var data = m_debugDataProvider.GetPopupData(m_testKey);
        var testVM = System.Activator.CreateInstance(
            typeof(PopupViewModel),
            data.Message,
            data.Subtitle,
            data.AnimationKey) as IPopupViewModel;
        Initialize(testVM);
    }
    #endregion

    #region 애니메이션 및 연출 로직
    private async UniTaskVoid StartShowSequence()
    {
        await ShowPanelAnimation();

        if (m_contentAnimator != null && !string.IsNullOrEmpty(m_viewModel.AnimationKey))
        {
            ResetAllAnimatorBools();
            m_contentAnimator.SetBool(m_viewModel.AnimationKey, true);
        }

        if (m_subtitleTypewriter != null && !string.IsNullOrEmpty(m_viewModel.Subtitle))
        {
            var lines = m_viewModel.Subtitle.Split('\n');
            var delayOneSecond = System.TimeSpan.FromSeconds(1.0f);
            var delayHalfSecond = System.TimeSpan.FromSeconds(0.5f);
            
            bool shouldContinueSubtitle = true;
            while (shouldContinueSubtitle)
            {
                for (int i = 0; i < lines.Length; i++)
                {
                    var line = lines[i];
                    if (string.IsNullOrWhiteSpace(line))
                    {
                        continue;
                    }
                    
                    await m_subtitleTypewriter.Play(m_subtitleText, line.Trim());
                    
                    await UniTask.Delay(delayOneSecond, cancellationToken: this.GetCancellationTokenOnDestroy());
                }

                if (m_loopSubtitle)
                {
                    await UniTask.Delay(delayHalfSecond, cancellationToken: this.GetCancellationTokenOnDestroy());
                }

                shouldContinueSubtitle = m_loopSubtitle;
            }
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

    public void func_CloseWithAnimation()
    {
        if (m_subtitleTypewriter != null)
        {
            m_subtitleTypewriter.Stop();
        }

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
        if (m_contentAnimator == null)
        {
            return;
        }

        var parameters = m_contentAnimator.parameters;
        for (int i = 0; i < parameters.Length; i++)
        {
            var param = parameters[i];
            if (param.type == AnimatorControllerParameterType.Bool)
            {
                m_contentAnimator.SetBool(param.name, false);
            }
        }
    }

    private void PlayTypingSound()
    {
    }

#endregion
}
#endregion
