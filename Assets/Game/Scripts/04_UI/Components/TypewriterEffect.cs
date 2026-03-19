using UnityEngine;
using TMPro;
using Cysharp.Threading.Tasks;
using System.Threading;

#region 내부 로직
/// <summary>
/// [설명]: 텍스트를 한 글자씩 출력하는 타이핑 효과를 담당하는 유틸리티 컴포넌트입니다.
/// </summary>
public class TypewriterEffect : MonoBehaviour
{
    #region 에디터 설정
    [SerializeField] private float m_typingSpeed = 0.05f;
    #endregion

    #region 프로퍼티
    public float TypingSpeed { get => m_typingSpeed; set => m_typingSpeed = value; }
    #endregion

    #region 내부 필드
    private CancellationTokenSource m_cts;
    private bool m_isTyping;
    #endregion

    #region 프로퍼티
    public bool IsTyping => m_isTyping;
    public event System.Action OnCharacterTyped;
    public event System.Action OnStartTyping;
    public event System.Action OnCompleteTyping;
    #endregion

    /// <summary>
    /// [설명]: 지정된 텍스트를 대상 TextMeshPro 요소에 타이핑 형식으로 출력합니다.
    /// </summary>
    /// <param name="tmpText">출력될 TMP 텍스트 컴포넌트</param>
    /// <param name="content">내용</param>
    /// <param name="onComplete">완료 시 콜백</param>
    public async UniTask Play(TMP_Text tmpText, string content, System.Action onComplete = null)
    {
        if (tmpText == null) return;

        Stop();
        m_cts = new CancellationTokenSource();
        m_isTyping = true;
        OnStartTyping?.Invoke();

        tmpText.text = "";
        
        try
        {
            for (int i = 1; i <= content.Length; i++)
            {
                tmpText.text = content.Substring(0, i);
                
                // 공백이 아닐 때만 효과음 이벤트 발생
                if (!char.IsWhiteSpace(content[i - 1]))
                {
                    OnCharacterTyped?.Invoke();
                }

                await UniTask.Delay(System.TimeSpan.FromSeconds(m_typingSpeed), cancellationToken: m_cts.Token);
            }
        }
        catch (System.OperationCanceledException)
        {
            // 스킵 시 전체 내용 즉시 출력
            tmpText.text = content;
        }
        finally
        {
            m_isTyping = false;
            OnCompleteTyping?.Invoke();
            onComplete?.Invoke();
        }
    }

    /// <summary>
    /// [설명]: 타이핑 진행 중 즉시 모든 텍스트를 출력하고 종료합니다.
    /// </summary>
    public void Skip()
    {
        if (m_isTyping)
        {
            m_cts?.Cancel();
        }
    }

    /// <summary>
    /// [설명]: 타이핑 효과를 중단합니다.
    /// </summary>
    public void Stop()
    {
        if (m_cts != null)
        {
            m_cts.Cancel();
            m_cts.Dispose();
            m_cts = null;
        }
        m_isTyping = false;
    }

    private void OnDestroy()
    {
        Stop();
    }
}
#endregion
