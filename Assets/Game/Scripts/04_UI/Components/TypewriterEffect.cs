using UnityEngine;
using TMPro;
using Cysharp.Threading.Tasks;
using System.Threading;

public class TypewriterEffect : MonoBehaviour
{
    [SerializeField] private float m_typingSpeed = 0.05f;

    public float TypingSpeed { get => m_typingSpeed; set => m_typingSpeed = value; }

    private CancellationTokenSource m_cts;
    private bool m_isTyping;

    public bool IsTyping => m_isTyping;
    public event System.Action OnCharacterTyped;
    public event System.Action OnStartTyping;
    public event System.Action OnCompleteTyping;

    public async UniTask Play(TMP_Text tmpText, string content, System.Action onComplete = null)
    {
        if (tmpText == null)
        {
            return;
        }

        Stop();
        tmpText.text = "";
        tmpText.maxVisibleCharacters = 99999;

        m_cts = new CancellationTokenSource();
        m_isTyping = true;
        
        if (OnStartTyping != null)
        {
            OnStartTyping.Invoke();
        }

        var delayTimeSpan = System.TimeSpan.FromSeconds(m_typingSpeed);
        
        try
        {
            for (int i = 1; i <= content.Length; i++)
            {
                tmpText.text = content.Substring(0, i);
                
                if (!char.IsWhiteSpace(content[i - 1]))
                {
                    if (OnCharacterTyped != null)
                    {
                        OnCharacterTyped.Invoke();
                    }
                }

                await UniTask.Delay(delayTimeSpan, cancellationToken: m_cts.Token);
            }
        }
        catch (System.OperationCanceledException)
        {
            tmpText.text = content;
        }
        finally
        {
            m_isTyping = false;
            
            if (OnCompleteTyping != null)
            {
                OnCompleteTyping.Invoke();
            }
            if (onComplete != null)
            {
                onComplete.Invoke();
            }
        }
    }

    public void Skip()
    {
        if (m_isTyping)
        {
            if (m_cts != null)
            {
                m_cts.Cancel();
            }
        }
    }

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
