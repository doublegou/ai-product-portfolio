"""Plot frozen Base V3 evidence; no inferred or synthetic performance data."""
from pathlib import Path
import csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'src/river_sr/training/base/v3'
font=Path('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
if font.exists():
 font_manager.fontManager.addfont(str(font));plt.rcParams['font.family']=font_manager.FontProperties(fname=str(font)).get_name()
plt.rcParams.update({'font.size':12,'axes.spines.top':False,'axes.spines.right':False,'axes.spines.left':False,'axes.labelcolor':'#344d59','text.color':'#183b47','xtick.color':'#526975','ytick.color':'#526975','figure.facecolor':'#f6f8fa','axes.facecolor':'#f6f8fa'})
def get(p):
 with p.open() as f:return {r['model']:r for r in csv.DictReader(f)}
p=get(BASE/'validation/primary_pooled_metrics.csv');s=get(BASE/'validation/primary_site_mean_metrics.csv');t=get(BASE/'release/training_metrics.csv')
fig,(a,b)=plt.subplots(1,2,figsize=(12,5.2),gridspec_kw={'width_ratios':[1,1.35]})
fig.subplots_adjust(top=.72,bottom=.2,left=.08,right=.97,wspace=.35)
fig.text(.05,.91,'选择 RF，同时限制高值用途',size=23,weight='bold')
fig.text(.05,.83,'同一次正式运行 · 同口径比较 · 不把训练拟合当成陌生水系表现',size=12)
vals=[float(p[m]['rmse']) for m in ['rf','xgb']]
a.barh(['RF','XGBoost'],vals,color=['#237b83','#8c9db5'],height=.45);a.invert_yaxis();a.set_xlim(0,.023);a.set_xlabel('严格 pooled OOF RMSE ↓');a.set_xticks([0,.01,.02]);a.grid(axis='x',alpha=.16);a.set_axisbelow(True)
for y,v in enumerate(vals):a.text(v+.0005,y,f'{v:.6f}',va='center',size=12)
xs=[0,1];b.bar([x-.18 for x in xs],[float(t[m]['hit_080_count']) for m in ['rf','xgb']],width=.34,label='训练拟合',color='#8c9db5');b.bar([x+.18 for x in xs],[float(s[m]['hit_080_count']) for m in ['rf','xgb']],width=.34,label='严格站点均值 OOF',color='#d78852');b.set_xticks(xs,['RF','XGBoost']);b.set_ylim(0,39);b.set_yticks([0,10,20,29]);b.set_ylabel('Sr ≥ 0.80 命中站点数 / 29');b.grid(axis='y',alpha=.16);b.set_axisbelow(True);b.legend(loc='upper left',frameon=False,fontsize=10)
for x,m in zip(xs,['rf','xgb']):
 b.text(x-.18,float(t[m]['hit_080_count'])+.6,f"{int(float(t[m]['hit_080_count']))}/29",ha='center',size=12)
 b.text(x+.18,1,'0/29',ha='center',color='#ac5828',weight='bold')
fig.text(.05,.065,'来源：base_v3_full_20260817_r2 · pooled 16,800 条预测；站点均值 5,600 站点 · 比值无量纲',size=10,color='#526975')
out=ROOT/'demo/assets';fig.savefig(out/'model-evidence.png',dpi=180);fig.savefig(out/'model-evidence.svg');plt.close(fig)
